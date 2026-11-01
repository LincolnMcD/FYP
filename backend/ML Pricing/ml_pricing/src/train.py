import argparse, json, time
from datetime import datetime, timezone
from pathlib import Path
import pandas as pd
from catboost import CatBoostRegressor, Pool
from .config import ROOT, DATASET, TARGET, CATEGORICAL, BASE_PARAMS
from .data_loader import load_data, write_report
from .preprocessing import make_xy
from .splits import random_row_split, model_group_split, split_report
from .evaluate import metric_summary, error_breakdowns, save_figures
from .progress import TrainingProgress, save_learning_history


def train_all(data_path=DATASET, strategies=("random", "group"), iterations=None, log_every=1, configurations=("with_model", "without_model")):
    if log_every < 1 or (iterations is not None and iterations < 1):
        raise ValueError("iterations and log_every must be positive")
    df, quality = load_data(data_path)
    print(json.dumps(quality, indent=2, default=str))
    write_report(quality, ROOT/"reports"/"data_quality.json")
    results, comparison = {}, []
    all_model_names = {}
    for strategy in strategies:
        splits = random_row_split(df) if strategy == "random" else model_group_split(df)
        split_meta = split_report(df, splits)
        (ROOT/"reports"/f"{strategy}_split.json").write_text(json.dumps(split_meta, indent=2), encoding="utf-8")
        for configuration in configurations:
            X, y = make_xy(df, configuration)
            tr, va, te = (splits[k] for k in ("train", "validation", "test"))
            pools = [Pool(X.iloc[i], y.iloc[i], cat_features=CATEGORICAL[configuration]) for i in (tr, va, te)]
            params = BASE_PARAMS.copy()
            if iterations is not None: params["iterations"] = iterations
            params.update(verbose=False, custom_metric=["MAE", "R2"], metric_period=1)
            model = CatBoostRegressor(**params)
            key = f"{strategy}_{configuration}"
            print(f"\n{key} | train={len(tr):,} validation={len(va):,} test={len(te):,}")
            print("Live metrics measure retention ratio. Final price metrics measure MYR.")
            progress = TrainingProgress(params["iterations"], log_every)
            started = time.perf_counter()
            model.fit(pools[0], eval_set=pools[1], early_stopping_rounds=100, use_best_model=True, callbacks=[progress])
            duration = time.perf_counter() - started
            if progress.last.iteration % log_every and progress.last.iteration != params["iterations"]:
                progress.display(progress.last)
            save_learning_history(model, ROOT/"reports", key)
            print(f"Best validation iteration: {model.best_iteration_ + 1}; retained trees: {model.tree_count_}")
            model_dir = ROOT/"models"/strategy
            model_dir.mkdir(parents=True, exist_ok=True)
            model_path = model_dir/f"catboost_{configuration}.cbm"
            model.save_model(model_path)
            pred = model.predict(pools[2])
            metrics = metric_summary(y.iloc[te], pred, df.iloc[te].msrp, df.iloc[te].actualSoldPrice)
            test_df = df.iloc[te].copy()
            pred_price = test_df.msrp.to_numpy() * __import__("numpy").clip(pred, 0, .9999)
            metrics["error_breakdowns"] = error_breakdowns(test_df, pred_price, set(df.iloc[tr].model))
            metrics["training_seconds"] = duration
            metrics["best_iteration"] = int(model.best_iteration_)
            metrics["split"] = split_meta
            (ROOT/"reports"/f"{key}_metrics.json").write_text(json.dumps(metrics, indent=2, default=str), encoding="utf-8")
            save_figures(test_df, pred, model, ROOT/"reports"/"figures", key)
            meta = {"dataset_version":"rebyte_depreciation_500000_AGE_BALANCED_12columns", "dataset_path":str(Path(data_path).resolve()),
                    "training_date_utc":datetime.now(timezone.utc).isoformat(), "feature_names":X.columns.tolist(),
                    "categorical_feature_names":CATEGORICAL[configuration], "hyperparameters":model.get_params(),
                    "model_version":"catboost_v1", "configuration":configuration, "strategy":strategy,
                    "best_iteration":int(model.best_iteration_), "evaluation_metrics":metrics,
                    "supported_brand_list":sorted(df.brand.unique().tolist()), "training_model_list":sorted(df.iloc[tr].model.unique().tolist()),
                    "input_validation_constraints":{"deviceAge":[0,10],"ramCapacity":">0","storage":">0","internalPerfromanceOverallMark":[0,100],"screenDmgScore":">=0","totalDmgScore":">=0","hasScreenDamage":[0,1],"msrp":">0"}}
            (model_dir/f"{configuration}_metadata.json").write_text(json.dumps(meta, indent=2, default=str), encoding="utf-8")
            all_model_names[key] = str(model_path)
            comparison.append({"configuration":configuration,"evaluation_strategy":strategy,"training_records":len(tr),"validation_records":len(va),"test_records":len(te),"retention_mae":metrics["retention_mae"],"price_mae_myr":metrics["price_mae_myr"],"price_rmse_myr":metrics["price_rmse_myr"],"price_r2":metrics["price_r2"],"training_time_seconds":duration})
            results[key] = metrics
            print(f"{key}: Price MAE RM{metrics['price_mae_myr']:.2f}; train {duration:.1f}s")
    comp = pd.DataFrame(comparison)
    (ROOT/"reports").mkdir(exist_ok=True)
    comp.to_csv(ROOT/"reports"/"model_comparison.csv", index=False)
    (ROOT/"models"/"model_paths.json").write_text(json.dumps(all_model_names, indent=2), encoding="utf-8")
    (ROOT/"models"/"training_metadata.json").write_text(json.dumps({"dataset_version":"rebyte_depreciation_500000_AGE_BALANCED_12columns","models":all_model_names,"results":comparison}, indent=2), encoding="utf-8")
    (ROOT/"reports"/"evaluation_metrics.json").write_text(json.dumps(results, indent=2, default=str), encoding="utf-8")
    schema = {"features":{"with_model":list(make_xy(df,"with_model")[0].columns),"without_model":list(make_xy(df,"without_model")[0].columns)},"categorical":CATEGORICAL,"target":TARGET,"forbidden_features":["actualSoldPrice",TARGET]}
    (ROOT/"models"/"feature_schema.json").write_text(json.dumps(schema, indent=2), encoding="utf-8")
    # Convenient production default aliases point at the random split artifacts.
    for conf in ("with_model", "without_model"):
        src=ROOT/"models"/"random"/f"catboost_{conf}.cbm"
        if src.exists():
            import shutil; shutil.copy2(src, ROOT/"models"/f"catboost_{conf}.cbm")
    return comp


if __name__ == "__main__":
    parser=argparse.ArgumentParser(); parser.add_argument("--data",default=str(DATASET)); parser.add_argument("--strategy",choices=["random","group","both"],default="both"); parser.add_argument("--iterations",type=int)
    parser.add_argument("--log-every", type=int, default=1, help="Print every N iterations; history always records every iteration")
    parser.add_argument("--configuration", choices=["with_model", "without_model", "both"], default="both", help="Select which feature configuration to train")
    args=parser.parse_args(); print(train_all(args.data,("random","group") if args.strategy=="both" else (args.strategy,),args.iterations,args.log_every,("with_model","without_model") if args.configuration=="both" else (args.configuration,)).to_string(index=False, float_format=lambda v: f"{v:.4f}"))
