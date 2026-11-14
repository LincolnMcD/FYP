import { load } from 'cheerio';

const arena = 'https://www.gsmarena.com/';
const androidList = 'https://storage.googleapis.com/play_public/supported_devices.csv';
const appleList = 'https://support.apple.com/en-us/108044';

export class SourceError extends Error {}

async function fetchPage(url, source) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(12_000) });
    if (!response.ok) throw new Error('HTTP ' + response.status);
    return response;
  } catch (error) {
    throw new SourceError(source + ' could not be reached (' + error.message + ').', { cause: error });
  }
}

function cached(read, ttl) {
  let promise;
  let expires = 0;
  return () => {
    if (!promise || Date.now() >= expires) {
      expires = Infinity;
      promise = Promise.resolve().then(read).then(
        (value) => {
          expires = Date.now() + ttl;
          return value;
        },
        (error) => {
          expires = 0;
          throw error;
        },
      );
    }
    return promise;
  };
}

const nameKey = (value) => value.normalize('NFKD').toLowerCase()
  .replace(/\+/g, ' plus ').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
const codeKey = (value) => value.toUpperCase().replace(/[^A-Z0-9]/g, '');

function parseBrands(html) {
  const $ = load(html);
  const brands = new Map();
  $('td > a[href]').each((_, link) => {
    const path = $(link).attr('href');
    const id = /^[\w-]+-phones-(\d+)\.php$/.exec(path)?.[1];
    if (!id) return;
    const name = $(link).clone().children().remove().end().text().trim();
    if (name) brands.set(nameKey(name), { id, name, path });
  });
  if (!brands.size) throw new SourceError('GSMArena’s brand directory is unavailable.');
  return brands;
}

const months = 'Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'.split(' ');

function announcement(title) {
  const match = /^(.*?)\.\s+Announced\s+(?:(\w+)\s+)?(\d{4})\b/i.exec(title);
  if (!match || !/phone$/i.test(match[1])) return null;
  const [, , period, yearText] = match;
  const year = Number(yearText);
  const month = months.indexOf(period);
  const quarter = /^Q([1-4])$/.exec(period)?.[1];
  const first = month >= 0 ? month : quarter ? (Number(quarter) - 1) * 3 : 0;
  const last = month >= 0 ? month : quarter ? first + 2 : 11;
  return {
    label: [period, year].filter(Boolean).join(' '),
    first: year * 12 + first,
    last: year * 12 + last,
  };
}

function parseBrandPage(html, brand) {
  const $ = load(html);
  const cards = $('.makers li > a[href]');
  if (!cards.length) throw new SourceError('GSMArena returned an unreadable brand listing.');
  const phones = [];
  cards.each((_, card) => {
    const path = $(card).attr('href');
    const id = /^([\w+()%.-]+)-(\d+)\.php$/.exec(path)?.[2];
    const name = $(card).find('strong').text().trim();
    const date = announcement($(card).find('img').attr('title') || '');
    if (id && name && date) {
      phones.push({ id: Number(id), name: brand.name + ' ' + name, url: new URL(path, arena).href, date });
    }
  });
  const pagePattern = new RegExp('^([\\w-]+-phones-f-' + brand.id + '-0-p)(\\d+)\\.php$');
  const pages = $('.nav-pages a[href]').toArray().flatMap((link) => {
    const match = pagePattern.exec($(link).attr('href'));
    return match ? [{ prefix: match[1], number: Number(match[2]) }] : [];
  });
  const lastPage = pages.sort((a, b) => b.number - a.number)[0];
  return { phones, lastPage };
}

function parseCatalog(home, feed) {
  const [brands, rows] = feed;
  if (!brands || !Array.isArray(rows) || !rows.length) {
    throw new SourceError('GSMArena returned an unfamiliar search index.');
  }
  return rows.flatMap(([brandId, id, model, aliases, thumbnail, override]) => {
    const brand = brands[brandId];
    if (!brand || !model || !Number.isSafeInteger(id)) return [];
    const officialName = brand + ' ' + model;
    const name = brand + ' ' + (override || model);
    const slug = officialName.toLowerCase().replace(/\s+|-|\/|\./g, '_');
    return [{
      id, name, url: new URL(slug + '-' + id + '.php', home).href,
      names: [...new Set([model, override || model, name, officialName].map(nameKey))],
      codeHints: (aliases || '').split(/\s+/).map(codeKey),
      thumbnail: thumbnail || '',
    }];
  });
}

function parseSpecs(html, url) {
  const $ = load(html);
  const name = $('[data-spec="modelname"]').first().text().trim();
  const sections = [];
  $('#specs-list table').each((_, table) => {
    const section = $(table).find('th').first().text().trim();
    const rows = [];
    $(table).find('tr').each((_, row) => {
      const label = $(row).children('td.ttl').text().trim();
      const valueCell = $(row).children('td.nfo');
      const key = valueCell.attr('data-spec') || null;
      valueCell.find('br').replaceWith('\n');
      const value = valueCell.text().split('\n')
        .map((line) => line.replace(/\s+/g, ' ').trim()).filter(Boolean).join('\n');
      if (value) rows.push({ label, key, value });
    });
    if (section && rows.length) sections.push({ section, rows });
  });
  if (!name || !sections.length) {
    throw new SourceError('GSMArena did not return a readable phone spec page.');
  }
  const modelCodes = sections.flatMap(({ rows }) => rows
    .filter(({ key, label }) => key === 'models' || label.toLowerCase() === 'models')
    .flatMap(({ value }) => value.split(/[,;\n]/).map((code) => code.trim()).filter(Boolean)));
  return { name, url, modelCodes, sections };
}

function parseAndroidModels(csv) {
  if (!csv.startsWith('Retail Branding,Marketing Name,Device,Model')) {
    throw new SourceError('Google Play returned an unfamiliar device list.');
  }
  const models = new Map();
  for (const line of csv.split(/\r?\n/).slice(1)) {
    const columns = /^"((?:[^"]|"")*)","((?:[^"]|"")*)","((?:[^"]|"")*)","((?:[^"]|"")*)"$/.exec(line);
    if (!columns) continue;
    const [, brand, marketingName, , model] = columns.map((column) => column.replace(/""/g, '"'));
    if (!marketingName || !model) continue;
    const key = codeKey(model);
    const names = models.get(key) || new Set();
    names.add(marketingName);
    if (brand) names.add(brand + ' ' + marketingName);
    models.set(key, names);
  }
  return models;
}

function parseAppleModels(html) {
  const $ = load(html);
  const models = new Map();
  let name;
  $('h2, p').each((_, node) => {
    const text = $(node).text().trim();
    if (node.name === 'h2') name = text.startsWith('iPhone') ? text : null;
    if (node.name === 'p' && name && /^Model numbers?:/i.test(text)) {
      for (const code of text.match(/\bA\d{4}\b/g) || []) models.set(code, [name]);
    }
  });
  if (!models.size) throw new SourceError('Apple returned an unfamiliar iPhone model list.');
  return models;
}

export function createScraper(getPage = fetchPage, now = () => new Date(), pageConcurrency = 3) {
  const day = 24 * 60 * 60 * 1000;
  const catalog = cached(async () => {
    const homepage = await (await getPage(arena, 'GSMArena')).text();
    const path = homepage.match(/\bAUTOCOMPLETE_LIST_URL\s*=\s*["'](\/quicksearch-\d+\.jpg)["']/)?.[1];
    if (!path) throw new SourceError('GSMArena’s phone search index is unavailable.');
    const response = await getPage(new URL(path, arena).href, 'GSMArena');
    let feed;
    try {
      feed = await response.json();
    } catch (error) {
      throw new SourceError('GSMArena’s phone search index could not be read.', { cause: error });
    }
    if (!Array.isArray(feed)) throw new SourceError('GSMArena returned an unfamiliar search index.');
    return parseCatalog(arena, feed);
  }, day);
  const androidModels = cached(async () => {
    const response = await getPage(androidList, 'Google Play’s device list');
    const csv = new TextDecoder('utf-16le').decode(await response.arrayBuffer());
    return parseAndroidModels(csv);
  }, day);
  const appleModels = cached(async () => parseAppleModels(
    await (await getPage(appleList, 'Apple’s iPhone model list')).text(),
  ), day);
  const brands = cached(async () => parseBrands(
    await (await getPage(new URL('makers.php3', arena).href, 'GSMArena')).text(),
  ), day);
  const brandReaders = new Map();
  const brandPhones = new Map();
  const specReaders = new Map();
  const verifiedCodes = new Map();

  function readBrand(brand) {
    if (!brandReaders.has(brand.id)) {
      brandReaders.set(brand.id, cached(async () => {
        async function readPage(path) {
          const response = await getPage(new URL(path, arena).href, 'GSMArena');
          return parseBrandPage(await response.text(), brand);
        }

        const { phones, lastPage } = await readPage(brand.path);
        // Read every page because catalog order can differ from announcement order.
        for (let page = 2; page <= (lastPage?.number || 1); page += pageConcurrency) {
          const batch = [];
          for (let offset = 0; offset < pageConcurrency && page + offset <= lastPage.number; offset++) {
            batch.push(readPage(lastPage.prefix + (page + offset) + '.php'));
          }
          for (const listing of await Promise.all(batch)) phones.push(...listing.phones);
        }
        return [...new Map(phones.map((phone) => [phone.id, phone])).values()];
      }, day));
    }
    return brandReaders.get(brand.id)();
  }

  function readSpecs(phone) {
    if (!specReaders.has(phone.id)) {
      specReaders.set(phone.id, cached(async () => {
        const response = await getPage(phone.url, 'GSMArena');
        const specs = parseSpecs(await response.text(), phone.url);
        for (const code of specs.modelCodes) {
          const key = codeKey(code);
          const ids = verifiedCodes.get(key) || new Set();
          ids.add(phone.id);
          verifiedCodes.set(key, ids);
        }
        return specs;
      }, day));
    }
    return specReaders.get(phone.id)();
  }

  function exactNames(phones, names) {
    const keys = new Set([...names].map(nameKey));
    return phones.filter((phone) => phone.names.some((name) => keys.has(name)));
  }

  async function findCode(phones, code) {
    const key = codeKey(code);
    if (!key) return [];
    const base = codeKey(code.split('/')[0]);
    const alreadyVerified = verifiedCodes.get(key);
    const hints = phones.filter((phone) => alreadyVerified?.has(phone.id) ||
      phone.codeHints.includes(key) || (key.length >= 5 && codeKey(phone.thumbnail).includes(key)));
    const inspected = new Set();

    async function confirm(candidates) {
      const matches = [];
      for (const phone of candidates) {
        if (inspected.has(phone.id)) continue;
        inspected.add(phone.id);
        const specs = await readSpecs(phone);
        if (specs.modelCodes.some((model) => codeKey(model) === key)) matches.push(phone);
      }
      return matches;
    }

    const direct = await confirm(hints.slice(0, 6));
    if (direct.length) return direct;

    const index = await (/^A\d{4}$/.test(key) ? appleModels() : androidModels());
    const possibleNames = index.get(key) || index.get(base);
    if (!possibleNames) return [];
    const names = [...possibleNames].flatMap((name) => [name, name.replace(/\s+5G$/i, '')]);
    return confirm(exactNames(phones, names).slice(0, 6));
  }

  const summary = ({ id, name, url }) => ({ id, name, url });
  const found = async (phone, matchedBy) => ({
    status: 'found', matchedBy, phone: await readSpecs(phone),
  });

  return {
    async byBrand(brandName, { yearOnly = false } = {}) {
      const brand = (await brands()).get(nameKey(brandName));
      if (!brand) return { status: 'brand_not_found' };
      const today = now();
      const end = today.getFullYear() * 12 + today.getMonth();
      const start = yearOnly ? (today.getFullYear() - 10) * 12 : end - 120;
      const phones = (await readBrand(brand))
        .filter(({ date }) => date.last >= start && date.first <= (yearOnly ? today.getFullYear() * 12 + 11 : end))
        .sort((a, b) => b.date.first - a.date.first || a.name.localeCompare(b.name));
      return {
        status: 'brand',
        brand: brand.name,
        from: months[start % 12] + ' ' + Math.floor(start / 12),
        to: months[end % 12] + ' ' + Math.floor(end / 12),
        phones: phones.map((phone) => {
          brandPhones.set(phone.id, phone);
          return { ...summary(phone), announced: phone.date.label, year: Math.floor(phone.date.first / 12) };
        }),
      };
    },
    async lookup({ modelName = '', modelCode = '' }) {
      const phones = await catalog();
      const query = nameKey(modelName);
      const exact = query ? exactNames(phones, [modelName]) : [];
      if (exact.length === 1) return found(exact[0], 'name');
      if (modelCode) {
        const matches = await findCode(phones, modelCode);
        if (matches.length === 1) return found(matches[0], 'code');
        if (matches.length) return { status: 'choices', candidates: matches.map(summary) };
      }
      const partial = query ? phones.filter((phone) => phone.names.some((name) =>
        (' ' + name + ' ').includes(' ' + query + ' ') || name.startsWith(query),
      )) : [];
      const candidates = exact.length ? exact : partial;
      if (candidates.length) return { status: 'choices', candidates: candidates.slice(0, 12).map(summary) };
      return { status: 'not_found' };
    },
    async byId(id) {
      const phone = brandPhones.get(id) || (await catalog()).find((candidate) => candidate.id === id);
      return phone ? found(phone, 'selection') : { status: 'not_found' };
    },
  };
}
