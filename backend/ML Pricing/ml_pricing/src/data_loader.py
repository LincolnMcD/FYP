import json
import csv
import pandas as pd
from .config import DATASET, REQUIRED, NUMERIC


def load_data(path=DATASET):
    with open(path, "r", encoding="utf-8-sig", newline="") as stream:
        header = next(csv.reader(stream), [])
    duplicates = sorted({name for name in header if header.count(name) > 1})
    if duplicates:
        raise ValueError(f"Duplicate column names: {duplicates}")
    df = pd.read_csv(path)
    report = validate_data(df)
    # Canonicalize categorical strings once, identically for training and inference.
    for col in ("brand", "model"):
        df[col] = df[col].fillna("__UNKNOWN__").astype(str).str.strip().str.casefold()
        df.loc[df[col].eq(""), col] = "__UNKNOWN__"
    return df, report


def validate_data(df):
    duplicate_columns = df.columns[df.columns.duplicated()].tolist()
    missing_columns = sorted(set(REQUIRED) - set(df.columns))
    if duplicate_columns or missing_columns:
        raise ValueError(f"Duplicate columns: {duplicate_columns}; missing required columns: {missing_columns}")
    d = df.copy()
    errors = {}
    for col in NUMERIC:
        d[col] = pd.to_numeric(d[col], errors="coerce")
        errors[f"invalid_{col}"] = int(d[col].isna().sum())
    checks = {
        "deviceAge_out_of_range": ~d.deviceAge.between(0, 10),
        "ramCapacity_not_positive": d.ramCapacity <= 0,
        "storage_not_positive": d.storage <= 0,
        "performance_out_of_range": ~d.internalPerfromanceOverallMark.between(0, 100),
        "negative_screen_damage": d.screenDmgScore < 0,
        "negative_total_damage": d.totalDmgScore < 0,
        "invalid_screen_damage_flag": ~d.hasScreenDamage.isin([0, 1]),
        "msrp_not_positive": d.msrp <= 0,
        "sold_price_invalid": (d.actualSoldPrice <= 0) | (d.actualSoldPrice >= d.msrp),
        "ratio_invalid": ~d.retentationRatio.between(0, 1, inclusive="neither"),
        "ratio_price_mismatch": (d.retentationRatio - d.actualSoldPrice / d.msrp).abs() > 1e-6,
    }
    errors.update({k: int(v.fillna(True).sum()) for k, v in checks.items()})
    invalid_rows = int(pd.DataFrame(checks).fillna(True).any(axis=1).sum())
    if invalid_rows:
        raise ValueError(f"Dataset has {invalid_rows} invalid rows; error counts: {errors}")
    return {"records": int(len(d)), "brands": int(d.brand.nunique()), "models": int(d.model.nunique()),
            "records_per_age": {str(k): int(v) for k, v in d.deviceAge.value_counts().sort_index().items()},
            "missing_values": {k: int(v) for k, v in df.isna().sum().items()}, "invalid_records": invalid_rows,
            "price_distribution_myr": d.actualSoldPrice.describe().round(2).to_dict(),
            "retention_distribution": d.retentationRatio.describe().round(6).to_dict(), "error_counts": errors}


def write_report(report, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2), encoding="utf-8")
