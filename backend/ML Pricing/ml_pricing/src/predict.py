import numpy as np
from pathlib import Path
from .config import ROOT, MODEL_WITH, MODEL_WITHOUT
from .preprocessing import prepare_features


class PricePredictor:
    def __init__(self, configuration="without_model", model_path=None):
        if configuration not in ("with_model", "without_model"):
            raise ValueError("configuration must be with_model or without_model")
        self.configuration = configuration
        self.schema = MODEL_WITH if configuration == "with_model" else MODEL_WITHOUT
        self.model_path = Path(model_path or ROOT/"models"/f"catboost_{configuration}.cbm")
        from catboost import CatBoostRegressor
        self.model = CatBoostRegressor()
        self.model.load_model(str(self.model_path))

    def predict(self, request):
        validate_request(request)
        X = prepare_features(__import__("pandas").DataFrame([request]), self.configuration)
        if X.columns.tolist() != self.schema:
            raise ValueError("Input feature schema mismatch")
        ratio = float(np.clip(self.model.predict(X)[0], 0.0, 0.9999))
        price = round(float(request["msrp"]) * ratio, 2)
        # Currency rounding can only lower the bound by a cent when MSRP is unusually small.
        price = min(price, round(float(request["msrp"]) - 0.01, 2)) if request["msrp"] >= 0.01 else 0.0
        return {"predictedRetentionRatio":ratio,"estimatedSellingPrice":price,"currency":"MYR","modelVersion":"catboost_v1","modelConfiguration":self.configuration}


def validate_request(d):
    required = MODEL_WITH
    missing = [k for k in required if k not in d]
    if missing: raise ValueError(f"Missing required fields: {', '.join(missing)}")
    for k in ("deviceAge","ramCapacity","storage","internalPerfromanceOverallMark","screenDmgScore","totalDmgScore","hasScreenDamage","msrp"):
        try: d[k] = float(d[k])
        except (TypeError,ValueError): raise ValueError(f"{k} must be numeric")
        if not np.isfinite(d[k]): raise ValueError(f"{k} must be finite")
    if not 0 <= d["deviceAge"] <= 10: raise ValueError("deviceAge must be between 0 and 10")
    if not d["deviceAge"].is_integer(): raise ValueError("deviceAge must be an integer")
    if d["ramCapacity"] <= 0 or d["storage"] <= 0: raise ValueError("ramCapacity and storage must be positive")
    if not d["ramCapacity"].is_integer() or not d["storage"].is_integer(): raise ValueError("ramCapacity and storage must be integers")
    if not 0 <= d["internalPerfromanceOverallMark"] <= 100: raise ValueError("internalPerfromanceOverallMark must be between 0 and 100")
    if d["screenDmgScore"] < 0 or d["totalDmgScore"] < 0: raise ValueError("damage scores must be nonnegative")
    if d["hasScreenDamage"] not in (0, 1): raise ValueError("hasScreenDamage must be 0 or 1")
    if d["msrp"] <= 0: raise ValueError("msrp must be greater than zero")
    for k in ("brand","model"):
        if not isinstance(d[k],str) or not d[k].strip(): raise ValueError(f"{k} must be a non-empty string")
