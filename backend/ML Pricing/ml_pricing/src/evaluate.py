import json
import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score, median_absolute_error


def metric_summary(y_ratio, pred_ratio, msrp, actual_price):
    pred_price = np.asarray(msrp) * np.clip(np.asarray(pred_ratio), 0.0, 0.9999)
    return {"retention_mae": float(mean_absolute_error(y_ratio, pred_ratio)),
            "retention_rmse": float(np.sqrt(mean_squared_error(y_ratio, pred_ratio))),
            "retention_r2": float(r2_score(y_ratio, pred_ratio)),
            "price_mae_myr": float(mean_absolute_error(actual_price, pred_price)),
            "price_rmse_myr": float(np.sqrt(mean_squared_error(actual_price, pred_price))),
            "price_r2": float(r2_score(actual_price, pred_price)),
            "price_median_absolute_error_myr": float(median_absolute_error(actual_price, pred_price))}


def error_breakdowns(df, pred_price, training_models=None):
    d = df.copy()
    d["absolute_error_myr"] = np.abs(d.actualSoldPrice.to_numpy() - pred_price)
    bins = [(0, 1, "0-1"), (1, 3, "1-3"), (3, 5, "3-5"), (5, 8, "5-8"), (8, 11, "8-10")]
    d["age_range"] = pd.cut(d.deviceAge, bins=[-0.01, 1, 3, 5, 8, 10], labels=[x[2] for x in bins], include_lowest=True)
    d["msrp_range"] = pd.cut(d.msrp, bins=[0, 1000, 2000, 4000, 8000, np.inf], labels=["<=1k", "1-2k", "2-4k", "4-8k", ">8k"])
    d["performance_range"] = pd.cut(d.internalPerfromanceOverallMark, bins=[-0.01, 40, 60, 80, 100], labels=["0-40", "40-60", "60-80", "80-100"], include_lowest=True)
    d["damage_range"] = pd.cut(d.totalDmgScore, bins=[-0.01, 10, 30, 60, np.inf], labels=["0-10", "10-30", "30-60", ">60"], include_lowest=True)
    out = {}
    for key, col in [("by_device_age", "deviceAge"), ("by_brand", "brand"), ("by_msrp_range", "msrp_range"), ("by_performance_range", "performance_range"), ("by_total_damage_range", "damage_range")]:
        out[key] = d.groupby(col, observed=False).absolute_error_myr.agg(["mean", "count"]).rename(columns={"mean":"mae_myr"}).reset_index().to_dict("records")
    if training_models is not None:
        d["model_exposure"] = np.where(d.model.isin(training_models), "seen", "unseen")
        out["seen_vs_unseen_models"] = d.groupby("model_exposure").absolute_error_myr.agg(["mean", "count"]).rename(columns={"mean":"mae_myr"}).reset_index().to_dict("records")
    return out


def save_figures(df, ratio, model, outdir, prefix):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    outdir.mkdir(parents=True, exist_ok=True)
    pred_price = np.clip(ratio, 0, .9999) * df.msrp.to_numpy()
    actual = df.actualSoldPrice.to_numpy()
    err = pred_price - actual
    fig, ax = plt.subplots(); ax.scatter(actual, pred_price, s=3, alpha=.15); ax.set(xlabel="Actual price (MYR)", ylabel="Predicted price (MYR)"); fig.savefig(outdir/f"{prefix}_actual_vs_predicted.png", dpi=140); plt.close(fig)
    fig, ax = plt.subplots(); ax.hist(err, bins=60); ax.set(xlabel="Prediction error (MYR)", ylabel="Count"); fig.savefig(outdir/f"{prefix}_error_distribution.png", dpi=140); plt.close(fig)
    tmp = pd.DataFrame({"age":df.deviceAge, "error":np.abs(err)}).groupby("age").error.mean()
    fig, ax = plt.subplots(); tmp.plot.bar(ax=ax); ax.set(xlabel="Device age", ylabel="MAE (MYR)"); fig.savefig(outdir/f"{prefix}_mae_by_age.png", dpi=140); plt.close(fig)
    tmp = pd.DataFrame({"brand":df.brand, "error":np.abs(err)}).groupby("brand").error.mean().sort_values()
    fig, ax = plt.subplots(figsize=(9,6)); tmp.plot.barh(ax=ax); ax.set(xlabel="MAE (MYR)"); fig.tight_layout(); fig.savefig(outdir/f"{prefix}_mae_by_brand.png", dpi=140); plt.close(fig)
    fig, ax = plt.subplots(); ax.scatter(df.retentationRatio, ratio, s=3, alpha=.15); ax.set(xlabel="Actual retention ratio", ylabel="Predicted retention ratio"); fig.savefig(outdir/f"{prefix}_retention.png", dpi=140); plt.close(fig)
    imp = pd.Series(model.feature_importances_, index=model.feature_names_).sort_values()
    fig, ax = plt.subplots(figsize=(8,5)); imp.plot.barh(ax=ax); ax.set(xlabel="Feature importance"); fig.tight_layout(); fig.savefig(outdir/f"{prefix}_feature_importance.png", dpi=140); plt.close(fig)
