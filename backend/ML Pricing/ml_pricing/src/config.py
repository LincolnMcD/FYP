from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parent
DATASET = WORKSPACE / "dataset 12col.csv"
TARGET = "retentationRatio"
PRICE_TARGET = "actualSoldPrice"
SEED = 42
MODEL_WITH = ["deviceAge", "brand", "model", "ramCapacity", "storage", "internalPerfromanceOverallMark", "screenDmgScore", "totalDmgScore", "hasScreenDamage", "msrp"]
MODEL_WITHOUT = ["deviceAge", "brand", "ramCapacity", "storage", "internalPerfromanceOverallMark", "screenDmgScore", "totalDmgScore", "hasScreenDamage", "msrp"]
CATEGORICAL = {"with_model": ["brand", "model"], "without_model": ["brand"]}
REQUIRED = ["deviceAge", "brand", "model", "ramCapacity", "storage", "internalPerfromanceOverallMark", "screenDmgScore", "totalDmgScore", "hasScreenDamage", "msrp", "actualSoldPrice", "retentationRatio"]
NUMERIC = ["deviceAge", "ramCapacity", "storage", "internalPerfromanceOverallMark", "screenDmgScore", "totalDmgScore", "hasScreenDamage", "msrp", "actualSoldPrice", "retentationRatio"]
BASE_PARAMS = dict(iterations=1500, depth=6, learning_rate=0.05, loss_function="RMSE", eval_metric="RMSE", l2_leaf_reg=3, random_seed=SEED, verbose=100, thread_count=-1)
