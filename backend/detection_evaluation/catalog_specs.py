"""Read assessment geometry and MSRP from the bundled GSMArena CSV."""

import csv
import json
import math
from pathlib import Path
import re

from .phone_specs import from_dimensions, normalized, _average_catalog_profile


CATALOG = Path(__file__).resolve().parents[1] / "phoneCatalog" / "gsmarena-models.csv"


def model_key(brand, model):
    key = normalized(model)
    return key.removeprefix(normalized(brand))


def lookup(brand, model, model_code=None):
    code_values = model_code if isinstance(model_code, list) else [model_code]
    wanted_codes = {
        key for value in code_values if isinstance(value, str)
        for code in re.split(r"[,|;]", value)
        if len(key := normalized(code)) >= 4
    }
    wanted_name = model_key(brand, model)
    matches = []
    if CATALOG.is_file():
        with CATALOG.open(encoding="utf-8-sig", newline="") as source:
            for row in csv.DictReader(source):
                if brand and normalized(row["brand"]) != normalized(brand):
                    continue
                raw_codes = row.get("modelCode") or row.get("model_codes") or ""
                codes = json.loads(raw_codes) if raw_codes.startswith("[") else re.split(r"[,|;]", raw_codes)
                code_match = any(normalized(code) in wanted_codes for code in codes)
                name_match = bool(wanted_name) and model_key(row["brand"], row["model"]) == wanted_name
                if code_match or name_match:
                    matches.append((2 * code_match + name_match, row))
    matches.sort(key=lambda match: match[0], reverse=True)
    if not matches or (len(matches) > 1 and matches[0][0] == matches[1][0]
                       and matches[0][1]["model"] != matches[1][1]["model"]):
        return _average_catalog_profile(brand, model, reason="No unique GSMArena catalog match.")
    row = matches[0][1]
    sections = json.loads(row.get("specs") or row.get("specifications") or "[]")
    values = {field["key"]: field.get("value", "") for section in sections for field in section["rows"]}
    body = re.search(r"(\d+(?:\.\d+)?)\s*[x×]\s*(\d+(?:\.\d+)?)\s*[x×]\s*(\d+(?:\.\d+)?)\s*mm",
                     values.get("dimensions", ""), re.IGNORECASE)
    diagonal = re.search(r"(\d+(?:\.\d+)?)\s*inches", values.get("displaysize", ""), re.IGNORECASE)
    resolution = re.search(r"(\d+)\s*[x×]\s*(\d+)", values.get("displayresolution", ""))
    if body and diagonal and resolution:
        height, width, depth = map(float, body.groups())
        short_px, long_px = sorted(map(int, resolution.groups()))
        scale = float(diagonal[1]) * 25.4 / math.hypot(short_px, long_px)
        catalog_model = row["model"]
        prefix = row["brand"] + " "
        if catalog_model.casefold().startswith(prefix.casefold()):
            catalog_model = catalog_model[len(prefix):]
        profile = from_dimensions(row["brand"], catalog_model, height, width, depth,
                                  short_px * scale, long_px * scale, "GSMArena CSV")
        profile["dimensions_method"] = "catalog_body_and_display_diagonal_resolution"
    else:
        profile = _average_catalog_profile(brand, model, reason="GSMArena catalog dimensions are incomplete.")
    for field in ("msrp", "listedPrice", "reported_price"):
        price = parse_price(row.get(field) or "")
        if price:
            currency, value = price
            profile["msrp" if currency == "MYR" else f"msrp_{currency.lower()}"] = value
            break
    return profile


def parse_price(price):
    amount = r"(\d[\d,]*(?:\.\d+)?)"
    for currency, prefix, suffix in (
        ("MYR", r"\b(?:MYR|RM)", r"(?:MYR|RM)\b"),
        ("USD", r"(?:US\$|(?<![\w])\$|\bUSD)", r"USD\b"),
        ("EUR", r"(?:€|\bEUR)", r"(?:EUR\b|€)"),
    ):
        for listing in price.split("/"):
            match = re.search(prefix + r"\s*" + amount + "|" + amount + r"\s*" + suffix,
                              listing.strip(), re.I)
            if match:
                value = float((match[1] or match[2]).replace(",", ""))
                if math.isfinite(value) and value > 0:
                    return currency, value
    return None
