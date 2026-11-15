"""Train a custom XGBoost-style model; NumPy/Pandas, no ML training library."""
import argparse
import time
from datetime import datetime
from pathlib import Path
import numpy as np
import pandas as pd
from .config import ROOT, DATASET, CATEGORICAL
from .data_loader import load_data
from .preprocessing import make_xy
from .scratch import regression_metrics
from .train_scratch import split_indices, save_report
from .xgboost_scratch import ScratchXGBoostRegressor


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', default=str(DATASET))
    parser.add_argument('--strategy', choices=['random', 'group'], default='group')
    parser.add_argument('--configuration', choices=['with_model', 'without_model'], default='with_model')
    parser.add_argument('--iterations', type=int, default=200)
    parser.add_argument('--depth', type=int, default=6)
    parser.add_argument('--bins', type=int, default=32)
    parser.add_argument('--learning-rate', type=float, default=.05)
    parser.add_argument('--l2', type=float, default=3.)
    parser.add_argument('--l1', type=float, default=0.)
    parser.add_argument('--gamma', type=float, default=0.)
    parser.add_argument('--min-child-weight', type=float, default=5.)
    parser.add_argument('--min-samples-leaf', type=int, default=5)
    parser.add_argument('--subsample', type=float, default=1.)
    parser.add_argument('--colsample-bytree', type=float, default=1.)
    parser.add_argument('--patience', type=int, default=50)
    parser.add_argument('--early-stopping-metric', choices=['price_mae', 'price_rmse', 'retention_rmse'], default='price_mae')
    parser.add_argument('--log-every', type=int, default=1)
    parser.add_argument('--max-rows', type=int)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--output', type=Path, default=ROOT/'xgboost_runs')
    args = parser.parse_args()
    if args.log_every < 1 or (args.max_rows is not None and args.max_rows < 3):
        parser.error('Require log-every>=1 and max-rows>=3')
    model = ScratchXGBoostRegressor(**{name: getattr(args, name) for name in
        ('iterations', 'depth', 'bins', 'learning_rate', 'l2', 'l1', 'gamma', 'min_child_weight',
         'min_samples_leaf', 'subsample', 'colsample_bytree', 'patience', 'seed', 'early_stopping_metric')})
    df, _ = load_data(args.data)
    if args.max_rows is not None and args.max_rows < len(df):
        df = df.sample(n=args.max_rows, random_state=args.seed).reset_index(drop=True)
    splits = split_indices(df, args.strategy, args.seed)
    X, y = make_xy(df, args.configuration)
    tr, va, te = (splits[key] for key in ('train', 'validation', 'test'))
    outdir = args.output/f'{args.strategy}_{args.configuration}_{datetime.now():%Y%m%d_%H%M%S_%f}'
    outdir.mkdir(parents=True)
    print(f'Custom XGBoost-style | {args.strategy}_{args.configuration} | {len(df):,} rows')
    print(f'Train: {len(tr):,} | Validation: {len(va):,} | Test: {len(te):,}')
    print(f'Early stopping: validation {args.early_stopping_metric}, patience={args.patience}')
    print(' Iter | Train RMSE | Valid RMSE | Train MAE | Valid MAE | Train R2 | Valid R2 | Val price MAE | Seconds')
    started = time.perf_counter()
    def progress(row):
        if row['iteration'] == 1 or row['iteration'] % args.log_every == 0:
            r2 = lambda v: '     n/a' if v is None else f'{v:8.4f}'
            print(f"{row['iteration']:5d} | {row['train_rmse']:10.6f} | {row['validation_rmse']:10.6f} | "
                  f"{row['train_mae']:9.6f} | {row['validation_mae']:9.6f} | "
                  f"{r2(row['train_r2'])} | {r2(row['validation_r2'])} | RM{row['validation_price_mae']:11.2f} | {time.perf_counter()-started:7.1f}", flush=True)
    model.fit(X.iloc[tr], y.iloc[tr], X.iloc[va], y.iloc[va], CATEGORICAL[args.configuration], progress,
              validation_msrp=df.iloc[va].msrp, validation_price=df.iloc[va].actualSoldPrice)
    duration = time.perf_counter()-started
    pred = model.predict(X.iloc[te])
    price = df.iloc[te].msrp.to_numpy()*np.clip(pred, 0, .9999)
    metrics = {'implementation': 'scratch_xgboost_v1', 'boosting': 'second_order_histogram',
               'categorical_encoding': 'training_only_one_hot', 'configuration': args.configuration,
               'strategy': args.strategy, 'training_seconds': duration, 'hyperparameters': model.params,
               'dataset': str(Path(args.data).resolve()), 'sample_rows': len(df), 'encoded_feature_count': len(model.specs),
               'best_iteration': model.best_iteration, 'attempted_iterations': len(model.history),
               'split': {key: {'records': len(idx), 'models': sorted(df.iloc[idx].model.unique().tolist())} for key, idx in splits.items()},
               'test_metrics': {'retention_ratio': regression_metrics(y.iloc[te], pred),
                                'price_myr': regression_metrics(df.iloc[te].actualSoldPrice, price)}}
    model.save(outdir/'model.json')
    model.feature_importance().to_csv(outdir/'feature_importance.csv', index=False)
    save_report(pd.DataFrame(model.history), metrics, outdir, model.best_iteration)
    # Additional price learning curves keep MYR units separate from retention metrics.
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    history = pd.DataFrame(model.history)
    fig, ax = plt.subplots(figsize=(9, 4))
    for metric in ('mae', 'rmse'):
        ax.plot(history.iteration, history[f'validation_price_{metric}'], label=f'Validation price {metric.upper()}')
    ax.axvline(model.best_iteration, color='gray', linestyle='--', label='Best iteration')
    ax.set(xlabel='Boosting iteration', ylabel='MYR', title='Validation price errors'); ax.legend(); ax.grid(alpha=.2)
    fig.tight_layout(); fig.savefig(outdir/'price_learning_curves.png', dpi=140); plt.close(fig)
    report = outdir/'report.html'
    report.write_text(report.read_text(encoding='utf-8').replace('</html>', '<h2>Validation price errors</h2><img src="price_learning_curves.png" alt="Validation price curves"></html>'), encoding='utf-8')
    print('\nHeld-out test metrics:\n'+pd.DataFrame(metrics['test_metrics']).T.to_string(float_format=lambda v: f'{v:.4f}'))
    print(f'Best iteration: {model.best_iteration}; retained trees: {len(model.trees)}')
    print(f'Model: {(outdir/"model.json").resolve()}\nReport: {report.resolve()}')


if __name__ == '__main__':
    main()
