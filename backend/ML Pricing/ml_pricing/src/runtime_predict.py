"""Inference entry point for the selected grouped phone retention model."""
import itertools
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

from .scratch import ScratchBoostRegressor


def predict(model_path, metrics_path, request_path):
    model = ScratchBoostRegressor.load(model_path)
    request = json.loads(Path(request_path).read_text(encoding="utf-8"))
    missing = [
        name for name in ("ramCapacity", "internalPerfromanceOverallMark")
        if request.get(name) is None
    ]
    frame = pd.DataFrame([request], columns=model.features)

    # A missing optional input is marginalized over its learned quantile bins,
    # so it is not treated as zero or as one arbitrary RAM/diagnostic score.
    candidates = []
    for name in missing:
        feature_index = model.encoded_feature_names.index(name)
        edges = model.borders[feature_index]
        values = []
        for index in range(len(edges) + 1):
            if not edges:
                values.append(0.0)
            elif index == 0:
                values.append(float(edges[0]))
            elif index < len(edges):
                values.append((float(edges[index - 1]) + float(edges[index])) / 2)
            else:
                step = float(edges[-1] - edges[-2]) if len(edges) > 1 else max(abs(float(edges[-1])) * 0.01, 1.0)
                values.append(float(edges[-1]) + step / 2)
        candidates.append((name, values))

    predictions = []
    combinations = itertools.product(*(values for _, values in candidates)) if candidates else [()]
    for values in combinations:
        row = frame.copy()
        for (name, _), value in zip(candidates, values):
            row.loc[0, name] = value
        predictions.append(float(model.predict(row)[0]))

    retention_ratio = float(np.clip(np.mean(predictions), 0.0, 0.9999))
    msrp = float(request["msrp"])
    actual_price = round(msrp * retention_ratio, 2)
    metrics = json.loads(Path(metrics_path).read_text(encoding="utf-8"))
    ratio_rmse = float(metrics["test_metrics"]["retention_ratio"]["rmse"])
    margin = msrp * ratio_rmse
    price_floor = min(30.0, msrp)
    return {
        "retentionRatio": retention_ratio,
        "actualPrice": actual_price,
        "margin": round(margin, 2),
        "min": round(max(price_floor, actual_price - margin), 2),
        "max": round(min(msrp, actual_price + margin), 2),
    }


def main():
    if len(sys.argv) != 4:
        raise SystemExit("Usage: runtime_predict.py <model.json> <metrics.json> <request.json>")
    print(json.dumps(predict(*sys.argv[1:]), allow_nan=False))


if __name__ == "__main__":
    main()
