"""Phone geometry lookup from the GetTechAPI TechAPI static JSON dataset."""
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen


def normalized(value):
    return re.sub(r'[^a-z0-9]', '', str(value or '').casefold())


def _canonical_brand_key(value):
    key = normalized(value)
    # TechAPI uses the corporate name while users commonly enter the short
    # consumer brand name.
    return {'lgelectronics': 'lg'}.get(key, key)


def _brand_display_name(record, requested_brand):
    record_brand = _record_brand_name(record, requested_brand)
    if _canonical_brand_key(record_brand) == _canonical_brand_key(requested_brand):
        if _canonical_brand_key(requested_brand) == 'lg':
            return 'LG'
        return str(requested_brand).strip().title()
    return record_brand.title()


PHONE_SPECS_API_BASE = 'https://gettechapi.github.io/TechAPI'
PHONE_SPECS_API_PROVIDER = 'TechAPI'
TECHAPI_LICENSE = 'CC-BY-SA 4.0; attribute “Data from TechAPI” and share alike.'
INDEX_CACHE_NAME = 'techapi_smartphones_index.json'
INDEX_CACHE_TTL_SECONDS = 7 * 24 * 60 * 60


def _model_key(value, brand):
    key = normalized(value)
    brand_key = normalized(brand)
    if brand_key and key.startswith(brand_key):
        key = key[len(brand_key):]
    return key


def from_dimensions(brand, model, height, width, thickness, screen_width,
                    screen_height, source):
    dimensions = [height, width, thickness, screen_width, screen_height]
    if any(not math.isfinite(float(v)) or v <= 0 for v in dimensions):
        raise ValueError('Phone dimensions must be positive numbers.')
    surfaces = {
        'Screen': {'width_mm': screen_width, 'height_mm': screen_height},
        'Back': {'width_mm': width, 'height_mm': height},
        'Frame_Left': {'width_mm': thickness, 'height_mm': height},
        'Frame_Right': {'width_mm': thickness, 'height_mm': height},
        'Frame_Top': {'width_mm': width, 'height_mm': thickness},
        'Frame_Bottom': {'width_mm': width, 'height_mm': thickness},
    }
    for row in surfaces.values():
        row.update(source=source, dimension_status='nominal_rectangle_estimate', exact_area=False)
    return {
        'brand': brand,
        'model': model,
        'phone_model': f'{brand} {model}',
        'source': source,
        'body_dimensions_mm': {'height': height, 'width': width, 'thickness': thickness},
        'surfaces': surfaces,
        'nominal_areas_cm2': {
            'Screen': screen_width * screen_height / 100,
            'Back': width * height / 100,
            'Frame': 2 * (width + height) * thickness / 100,
        },
        'required_surfaces': list(surfaces),
        'exact_part_areas_available': False,
        'geometry_notes': [
            'Screen rectangle excludes no rounded corners or cutouts.',
            'Back rectangle excludes no camera cutouts or curvature.',
            'Frame estimate is a rectangular-prism side area, not exact metal surface area.',
        ],
    }


def _site_and_api_base(base):
    base = (base or PHONE_SPECS_API_BASE).rstrip('/')
    parsed = urlparse(base)
    if not parsed.netloc or parsed.scheme != 'https':
        raise ValueError('TechAPI base URL must use HTTPS.')
    if parsed.path.rstrip('/').endswith('/v1'):
        return base[:-3], base
    return base, base + '/v1'


def _json_url(url):
    parsed = urlparse(url)
    if parsed.scheme != 'https' or not parsed.netloc:
        raise ValueError('TechAPI JSON URLs must use HTTPS.')
    request = Request(url, headers={
        'User-Agent': 'PhoneInspection/1.0',
        'Accept': 'application/json',
    })
    for attempt in range(2):
        try:
            with urlopen(request, timeout=60) as response:
                return json.load(response)
        except HTTPError as exc:
            body = exc.read(2048).decode('utf-8', 'replace').strip()
            if exc.code in (429, 500, 502, 503, 504) and attempt == 0:
                time.sleep(3)
                continue
            detail = ' '.join(body.split())[:600]
            raise URLError(f'HTTP {exc.code} for {exc.url}' + (f'; {detail}' if detail else '')) from exc


def _atomic_json_write(path, payload):
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + '.tmp')
        temporary.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding='utf-8')
        temporary.replace(path)
    except OSError:
        pass


def _load_index(site_base, api_base):
    cache_path = Path(__file__).with_name('phone_specs_cache') / INDEX_CACHE_NAME
    local_index_path = Path(__file__).with_name('index.json')
    cached = None
    try:
        cached = json.loads(cache_path.read_text(encoding='utf-8'))
    except (OSError, ValueError, TypeError, AttributeError):
        cached = None

    cache_payload = cached.get('payload') if isinstance(cached, dict) else None
    cache_time = 0.0
    if (isinstance(cached, dict) and cached.get('api_provider') == PHONE_SPECS_API_PROVIDER and
            cached.get('base_url', '').rstrip('/') == api_base.rstrip('/') and
            isinstance(cache_payload, dict) and isinstance(cache_payload.get('results'), list)):
        try:
            cache_time = float(cached.get('fetched_epoch', 0))
        except (TypeError, ValueError):
            cache_time = 0.0
    else:
        cache_payload = None

    local_payload = None
    local_time = 0.0
    try:
        local_payload = json.loads(local_index_path.read_text(encoding='utf-8'))
        if not isinstance(local_payload, dict) or not isinstance(local_payload.get('results'), list):
            local_payload = None
        else:
            local_time = local_index_path.stat().st_mtime
    except (OSError, ValueError, TypeError):
        local_payload = None

    if local_payload is not None and local_time >= cache_time:
        _atomic_json_write(cache_path, {
            'api_provider': PHONE_SPECS_API_PROVIDER,
            'base_url': api_base,
            'source': str(local_index_path),
            'fetched_epoch': local_time,
            'fetched_at': datetime.fromtimestamp(local_time, timezone.utc).isoformat(),
            'payload': local_payload,
        })
        return local_payload
    if cache_payload is not None and time.time() - cache_time < INDEX_CACHE_TTL_SECONDS:
        return cache_payload

    index_url = f'{api_base}/smartphones/index.json'
    try:
        payload = _json_url(index_url)
        if not isinstance(payload, dict) or not isinstance(payload.get('results'), list):
            raise ValueError('TechAPI smartphone index did not contain a results list.')
        _atomic_json_write(cache_path, {
            'api_provider': PHONE_SPECS_API_PROVIDER,
            'base_url': api_base,
            'source': index_url,
            'fetched_epoch': time.time(),
            'fetched_at': datetime.now(timezone.utc).isoformat(),
            'payload': payload,
        })
        return payload
    except (URLError, TimeoutError, ValueError):
        if local_payload is not None:
            return local_payload
        if cache_payload is not None:
            return cache_payload
        raise


def _model_tokens(model, brand):
    raw_model = str(model or '').strip()
    brand_text = str(brand or '').strip()
    if brand_text and raw_model.casefold().startswith(brand_text.casefold()):
        raw_model = raw_model[len(brand_text):].strip(' -:')
    return [normalized(token) for token in re.findall(r'[A-Za-z0-9]+', raw_model) if normalized(token)]


def _candidate_score(name, slug, brand, model):
    brand_key = normalized(brand)
    model_key = _model_key(model, brand)
    name_key = normalized(name)
    slug_key = normalized(slug)
    if not brand_key or not model_key:
        return 0
    # TechAPI index entries can omit the manufacturer from both `name` and
    # `slug` (for example `Galaxy A01` / `galaxy-a01`). Names and slugs can
    # also include storage, network, or regional variants. Match the requested
    # model phrase against either field so every relevant variant is tried;
    # the detail record's brand is checked before it can be used.
    candidate_model = _model_key(name, brand) if name_key.startswith(brand_key) else name_key
    if candidate_model == model_key:
        return 5

    def has_model_with_variant_tail(candidate):
        at = candidate.find(model_key)
        if at < 0:
            return False
        tail = candidate[at + len(model_key):]
        if not tail:
            return True
        # Permit storage/network/region suffixes while avoiding sibling
        # products such as "G3 Stylus" when the requested model is "G3".
        parts = re.findall(r'[a-z]{1,3}\d{2,4}[a-z0-9]*|\d+[a-z]*|[a-z]+', tail)
        if not parts:
            return True
        allowed_words = {
            '2g', '3g', '4g', '5g', 'lte', 'ltea', 'tdlte', 'cdma', 'gsm',
            'dual', 'sim', 'global', 'standard', 'premium', 'edition',
            'ram', 'rom', 'wifi', 'ds', 'volte', 'us', 'eu', 'in', 'latam',
        }
        for part in parts:
            if part in allowed_words or re.fullmatch(r'\d+(?:gb|tb|g|mb)?', part):
                continue
            if re.fullmatch(r'[a-z]{1,3}\d{2,4}[a-z0-9]*', part):
                continue  # regional/model code, e.g. D855
            return False
        return True

    if has_model_with_variant_tail(candidate_model):
        return 4
    if has_model_with_variant_tail(slug_key):
        return 3
    return 0


def _index_candidates(index_payload, brand, model):
    rows = [row for row in index_payload.get('results', []) if isinstance(row, dict)]
    scored = [( _candidate_score(row.get('name', ''), row.get('slug', ''), brand, model), row)
              for row in rows]
    candidates = []
    seen_slugs = set()
    for score, row in sorted(scored, key=lambda item: -item[0]):
        slug = str(row.get('slug') or '').strip()
        if score > 0 and slug and slug.casefold() not in seen_slugs:
            candidates.append(row)
            seen_slugs.add(slug.casefold())
    return candidates


def _detail_url(site_base, api_base, candidate):
    route = str(candidate.get('url') or '').strip()
    if route.startswith('https://'):
        return route.rstrip('/') + '/index.json'
    if route:
        return site_base.rstrip('/') + '/' + route.strip('/') + '/index.json'
    slug = quote(str(candidate.get('slug') or ''), safe='-_')
    return f'{api_base}/smartphones/{slug}/index.json'


def _record_cache_path(slug):
    return Path(__file__).with_name('phone_specs_cache') / f'techapi_record_{normalized(slug)}.json'


def _record_brand_name(record, fallback):
    brand = record.get('brand') or fallback
    if isinstance(brand, dict):
        brand = brand.get('name') or brand.get('slug') or fallback
    return str(brand).strip()


def _load_record(slug, detail_url):
    cache_path = _record_cache_path(slug)
    try:
        cached = json.loads(cache_path.read_text(encoding='utf-8'))
        if (cached.get('api_provider') == PHONE_SPECS_API_PROVIDER and
                cached.get('slug') == slug and isinstance(cached.get('payload'), dict)):
            return cached['payload']
    except (OSError, ValueError, TypeError, AttributeError):
        pass

    payload = _json_url(detail_url)
    if isinstance(payload, dict) and isinstance(payload.get('data'), dict):
        payload = payload['data']
    if not isinstance(payload, dict):
        raise ValueError(f'TechAPI detail record {slug} was not a JSON object.')
    _atomic_json_write(cache_path, {
        'api_provider': PHONE_SPECS_API_PROVIDER,
        'slug': slug,
        'source': detail_url,
        'fetched_at': datetime.now(timezone.utc).isoformat(),
        'payload': payload,
    })
    return payload


def _display_model_name(record, brand, requested_model):
    name = str(record.get('name') or '').strip()
    prefixes = [str(brand or '').strip(), _record_brand_name(record, brand)]
    for brand_name in prefixes:
        if brand_name and name and normalized(name).startswith(normalized(brand_name)):
            # Remove the brand using the original string length when it is a literal prefix.
            if name.casefold().startswith(brand_name.casefold()):
                name = name[len(brand_name):].strip(' -:')
            else:
                name = requested_model
            break
    return name or requested_model


def _display_size_and_resolution(record):
    display = record.get('display') or {}
    if not isinstance(display, dict):
        display = {}
    size_text = display.get('size_inch') or display.get('size') or display.get('diagonal_in')
    size_match = re.search(r'(\d+(?:\.\d+)?)', str(size_text or ''))
    if not size_match:
        raise ValueError('TechAPI record must include a usable display size in inches.')
    diagonal_in = float(size_match.group(1))
    if not math.isfinite(diagonal_in) or diagonal_in <= 0:
        raise ValueError('TechAPI display size must be positive.')
    resolution = str(display.get('resolution') or '')
    resolution_match = re.search(r'(\d{3,5})\s*[x×]\s*(\d{3,5})', resolution)
    return diagonal_in, resolution_match


def _battery_capacity_mah(record):
    value = record.get('battery_mah')
    if value is None and isinstance(record.get('battery'), dict):
        value = record['battery'].get('capacity_mah') or record['battery'].get('mah')
    match = re.search(r'(\d+(?:\.\d+)?)', str(value or ''))
    if not match:
        raise ValueError('TechAPI record must include battery capacity in mAh for the thickness estimate.')
    capacity = float(match.group(1))
    if not math.isfinite(capacity) or capacity <= 0:
        raise ValueError('TechAPI battery capacity must be positive.')
    return capacity


def _estimated_thickness_mm(capacity_mah):
    if capacity_mah < 4000:
        return 7.8
    if capacity_mah <= 4500:
        return 8.2
    if capacity_mah < 5000:
        # Interpolate through the unspecified 4501–4999 mAh interval.
        return 8.2 + (capacity_mah - 4500) * (0.7 / 500)
    return 8.9


def _parse_techapi_record(record, brand, requested_model, source):
    if not isinstance(record, dict):
        raise ValueError('TechAPI detail response was not an object.')
    brand_name = _brand_display_name(record, brand)
    model_name = _display_model_name(record, brand, requested_model)

    dimensions = record.get('dimensions') or record.get('body_dimensions_mm') or {}
    if not isinstance(dimensions, dict) and isinstance(record.get('body'), dict):
        dimensions = record['body'].get('dimensions') or record['body']
    height = dimensions.get('height_mm', dimensions.get('height')) if isinstance(dimensions, dict) else None
    width = dimensions.get('width_mm', dimensions.get('width')) if isinstance(dimensions, dict) else None
    thickness = dimensions.get('depth_mm', dimensions.get('thickness', dimensions.get('depth'))) if isinstance(dimensions, dict) else None
    try:
        height, width, thickness = float(height), float(width), float(thickness)
    except (TypeError, ValueError):
        raise ValueError('TechAPI record must include positive dimensions.height_mm, width_mm and depth_mm.')
    if any(not math.isfinite(value) or value <= 0 for value in (height, width, thickness)):
        raise ValueError('TechAPI record must include positive dimensions.height_mm, width_mm and depth_mm.')

    diagonal, resolution_match = _display_size_and_resolution(record)
    if not resolution_match:
        raise ValueError('TechAPI record must include display pixel resolution.')

    short, long = sorted(map(float, resolution_match.groups()))
    diagonal_mm = diagonal * 25.4
    ratio = long / short
    screen_width = diagonal_mm / math.sqrt(1 + ratio * ratio)
    screen_height = screen_width * ratio
    profile = from_dimensions(brand_name, model_name, height, width, thickness,
                              screen_width, screen_height, source)
    source_urls = record.get('source_urls') or []
    profile.update({
        'api_provider': PHONE_SPECS_API_PROVIDER,
        'data_attribution': 'Data from TechAPI',
        'data_license': TECHAPI_LICENSE,
        'source_urls': source_urls,
        'provider_raw': record,
        'fetched_at': datetime.now(timezone.utc).isoformat(),
    })
    return profile


def _parse_techapi_estimated_record(record, brand, requested_model, source):
    """Estimate missing chassis dimensions from display diagonal and battery size."""
    diagonal_in, resolution_match = _display_size_and_resolution(record)
    battery_mah = _battery_capacity_mah(record)
    diagonal_mm = diagonal_in * 25.4
    if resolution_match:
        short, long = sorted(map(float, resolution_match.groups()))
        aspect_ratio = long / short
        aspect_ratio_source = 'TechAPI display resolution'
    else:
        aspect_ratio = 20 / 9
        aspect_ratio_source = 'assumed 20:9 because display resolution was unavailable'
    screen_width = diagonal_mm / math.sqrt(1 + aspect_ratio ** 2)
    screen_height = screen_width * aspect_ratio
    chassis_width = screen_width + 6.5
    chassis_height = screen_height + 13.5
    thickness = _estimated_thickness_mm(battery_mah)
    brand_name = _brand_display_name(record, brand)
    model_name = _display_model_name(record, brand, requested_model)
    estimate_source = f'{source} (estimated geometry from display size and battery capacity)'
    profile = from_dimensions(brand_name, model_name, chassis_height, chassis_width,
                              thickness, screen_width, screen_height, estimate_source)
    profile.update({
        'api_provider': PHONE_SPECS_API_PROVIDER,
        'data_attribution': 'Data from TechAPI; body geometry estimated by the inspection app.',
        'data_license': TECHAPI_LICENSE,
        'source_urls': record.get('source_urls') or [],
        'provider_raw': record,
        'fetched_at': datetime.now(timezone.utc).isoformat(),
        'body_dimensions_method': 'estimated_from_display_size_and_battery_capacity',
        'body_dimensions_assumptions': {
            'display_diagonal_in': diagonal_in,
            'screen_aspect_ratio_height_to_width': aspect_ratio,
            'screen_aspect_ratio_source': aspect_ratio_source,
            'side_bezels_total_mm': 6.5,
            'top_and_bottom_bezels_total_mm': 13.5,
            'battery_capacity_mah': battery_mah,
            'estimated_thickness_mm': thickness,
        },
    })
    profile['geometry_notes'].extend([
        'Phone body dimensions are estimates because TechAPI did not provide height, width, and depth.',
        f'Screen dimensions use aspect ratio {aspect_ratio:.4g}:1 ({aspect_ratio_source}) and the listed display diagonal.',
        'Chassis dimensions add 6.5 mm total side bezel and 13.5 mm total top/bottom bezel.',
        'Thickness is a heuristic from battery capacity: below 4000 mAh = 7.8 mm; 4000–4500 mAh = 8.2 mm; 4501–4999 mAh is linearly interpolated; 5000 mAh or above = 8.9 mm.',
    ])
    return profile


def _lookup_techapi(brand, model, base, slug=None):
    site_base, api_base = _site_and_api_base(base)
    index_payload = _load_index(site_base, api_base)
    if slug:
        candidates = [{'slug': slug, 'url': f'/v1/smartphones/{slug}'}]
    else:
        candidates = _index_candidates(index_payload, brand, model)
    if not candidates:
        raise ValueError(f'TechAPI has no smartphone record matching {brand} {model}.')

    failures = []
    estimate_candidates = []
    checked = 0
    for candidate in candidates:
        phone_slug = str(candidate.get('slug') or '')
        if not re.fullmatch(r'[A-Za-z0-9_-]+', phone_slug):
            continue
        checked += 1
        detail_url = _detail_url(site_base, api_base, candidate)
        try:
            record = _load_record(phone_slug, detail_url)
            found_brand = _canonical_brand_key(_record_brand_name(record, brand))
            if found_brand != _canonical_brand_key(brand):
                failures.append(f'{phone_slug}: detail record manufacturer is {_record_brand_name(record, "unknown")!r}, not {brand!r}')
                continue
            found_model = str(record.get('name') or model)
            if _candidate_score(found_model, phone_slug, brand, model) == 0:
                continue
            estimate_candidates.append((record, detail_url))
            profile = _parse_techapi_record(record, brand, model, detail_url)
            profile['api_detail_url'] = detail_url
            profile['techapi_slug'] = phone_slug
            profile['source_urls'] = record.get('source_urls') or []
            return profile
        except (URLError, TimeoutError, ValueError) as exc:
            failures.append(f'{phone_slug}: {exc}')
    for record, detail_url in estimate_candidates:
        try:
            profile = _parse_techapi_estimated_record(record, brand, model, detail_url)
            profile['api_detail_url'] = detail_url
            profile['techapi_slug'] = str(record.get('slug') or '')
            return profile
        except ValueError as exc:
            failures.append(f'{record.get("slug") or "unknown slug"}: estimate unavailable: {exc}')
    if failures:
        examples = '; '.join(failures[:5])
        remaining = max(0, len(failures) - 5)
        suffix = f'; plus {remaining} other record failure(s)' if remaining else ''
        raise ValueError(f'TechAPI checked {checked} matching {brand} {model} record(s), but none had valid body dimensions and display data. ' +
                         examples + suffix)
    raise ValueError(f'TechAPI index entries did not include an exact brand/model record for {brand} {model}.')


def _profile_cache_file(brand, model):
    return Path(__file__).with_name('phone_specs_cache') / (normalized(brand + '_' + model) + '.json')


def _cached_api_profile(brand, model):
    path = _profile_cache_file(brand, model)
    if not path.is_file():
        return None
    try:
        profile = json.loads(path.read_text(encoding='utf-8'))
        if (profile.get('api_provider') == PHONE_SPECS_API_PROVIDER and profile.get('provider_raw') and
                normalized(profile.get('phone_model', '')) == normalized(brand + ' ' + model)):
            return path, profile
    except (OSError, ValueError, TypeError, AttributeError):
        pass
    return None


def _save_api_profile(brand, model, profile):
    _atomic_json_write(_profile_cache_file(brand, model), profile)


def _catalog_profile(brand, model, catalog_path=None):
    catalog = Path(catalog_path) if catalog_path else Path(__file__).with_name('phone_profiles.json')
    rows = json.loads(catalog.read_text(encoding='utf-8')).get('profiles', [])
    wanted = normalized(brand + ' ' + model)
    for row in rows:
        if normalized(row.get('phone_model', '')) == wanted:
            return row
    return None


def _average_catalog_profile(brand, model, catalog_path=None, reason=None):
    """Build an explicitly generic fallback from complete bundled phone profiles."""
    catalog = Path(catalog_path) if catalog_path else Path(__file__).with_name('phone_profiles.json')
    rows = json.loads(catalog.read_text(encoding='utf-8')).get('profiles', [])
    complete = []
    for row in rows:
        body = row.get('body_dimensions_mm') or {}
        screen = (row.get('surfaces') or {}).get('Screen') or {}
        try:
            values = [
                float(body['height']), float(body['width']), float(body['thickness']),
                float(screen['width_mm']), float(screen['height_mm']),
            ]
        except (KeyError, TypeError, ValueError):
            continue
        if all(math.isfinite(value) and value > 0 for value in values):
            complete.append((row, values))
    if not complete:
        raise ValueError('No complete bundled phone profiles are available for a generic dimension estimate.')

    averages = [sum(values[index] for _, values in complete) / len(complete) for index in range(5)]
    source = f'Arithmetic mean of {len(complete)} complete bundled phone profiles; generic estimate, not device-specific.'
    profile = from_dimensions(
        brand or 'Unknown', model, averages[0], averages[1], averages[2],
        averages[3], averages[4], source,
    )
    profile.update({
        'generic_fallback': True,
        'generic_fallback_reason': reason or 'No matching device profile was found.',
        'dimensions_method': 'arithmetic_mean_of_bundled_phone_profiles',
        'fallback_sample_count': len(complete),
        'fallback_profiles': [row.get('phone_model') for row, _ in complete],
        'body_dimensions_method': 'generic_average_fallback',
        'exact_part_areas_available': False,
    })
    profile['geometry_notes'].append(
        'All dimensions are an arithmetic mean of bundled profiles and are only a generic fallback; review measurements and grade.'
    )
    return profile


def lookup(brand, model, catalog_path=None, api_base=None, slug=None):
    brand = str(brand or '').strip()
    model = str(model or '').strip()
    if not brand or not model:
        raise ValueError('Enter both a phone brand and model name.')
    base = (api_base or PHONE_SPECS_API_BASE).rstrip('/')
    _site_and_api_base(base)

    cached = _cached_api_profile(brand, model)
    if cached and not slug:
        path, profile = cached
        profile['api_cache_reuse'] = {
            'used': True,
            'cached_profile_path': str(path),
            'cached_fetched_at': profile.get('fetched_at'),
        }
        return profile
    try:
        profile = _lookup_techapi(brand, model, base, slug)
        _save_api_profile(brand, model, profile)
        return profile
    except (URLError, TimeoutError, ValueError) as exc:
        cached = _cached_api_profile(brand, model)
        if cached:
            path, profile = cached
            profile['api_cache_fallback'] = {
                'used': True,
                'reason': str(exc),
                'cached_profile_path': str(path),
                'cached_fetched_at': profile.get('fetched_at'),
            }
            return profile
        local = _catalog_profile(brand, model, catalog_path)
        if local:
            local['local_profile_fallback'] = {'used': True, 'reason': str(exc)}
            return local
        return _average_catalog_profile(brand, model, catalog_path, reason=str(exc))


def _code_values(record):
    values = []
    keys = {'modelcode', 'modelcodes', 'modelnumber', 'modelnumbers', 'models', 'code', 'codes'}

    def visit(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if normalized(key) in keys:
                    values.append(child)
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(record)
    return values


def _has_exact_model_code(record, model_code):
    wanted = normalized(model_code)
    for value in _code_values(record):
        rows = value if isinstance(value, (list, tuple, set)) else [value]
        for row in rows:
            if normalized(row) == wanted:
                return True
            if wanted and wanted in normalized(row):
                return True
    return False


def lookup_model_code(model_code, api_base=None):
    model_code = str(model_code or '').strip()
    if not model_code:
        raise ValueError('Enter a phone model code.')
    cache_dir = Path(__file__).with_name('phone_specs_cache')
    for path in cache_dir.glob('*.json'):
        if path.name == INDEX_CACHE_NAME or path.name.startswith('techapi_record_'):
            continue
        try:
            profile = json.loads(path.read_text(encoding='utf-8'))
            if (profile.get('api_provider') == PHONE_SPECS_API_PROVIDER and
                    _has_exact_model_code(profile.get('provider_raw') or {}, model_code)):
                return profile
        except (OSError, ValueError, TypeError, AttributeError):
            continue
    raise ValueError('TechAPI does not expose a reliable model-code search. Enter the phone brand and model name instead.')
