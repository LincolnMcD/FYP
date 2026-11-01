"""CLI for the from-scratch educational trainer; no ML training libraries."""
import argparse
import json
import time
from pathlib import Path
import numpy as np
import pandas as pd
from .config import DATASET, ROOT, CATEGORICAL
from .data_loader import load_data
from .preprocessing import make_xy
from .scratch import ScratchBoostRegressor, regression_metrics


def split_indices(df, strategy, seed):
    rng = np.random.default_rng(seed)
    units = np.unique(df.model) if strategy == 'group' else np.arange(len(df))
    if len(units) < 3:
        raise ValueError('At least 3 split units (models for group splitting) required')
    units = rng.permutation(units)
    n_test = max(1, round(.15 * len(units)))
    n_valid = min(max(1, round(.15 * len(units))), len(units) - n_test - 1)
    parts = {'test': units[:n_test], 'validation': units[n_test:n_test+n_valid],
             'train': units[n_test+n_valid:]}
    return {key: np.flatnonzero(np.isin(df.model.to_numpy(), part)) if strategy == 'group' else part
            for key, part in parts.items()}


def save_report(history, metrics, outdir, best_iteration):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    history.to_csv(outdir / 'learning_history.csv', index=False)
    (outdir / 'metrics.json').write_text(json.dumps(metrics, indent=2, allow_nan=False), encoding='utf-8')
    fig, axes = plt.subplots(1, 3, figsize=(15, 4))
    for ax, metric in zip(axes, ('rmse', 'mae', 'r2')):
        for split in ('train', 'validation'):
            ax.plot(history.iteration, history[f'{split}_{metric}'], label=split)
        ax.axvline(best_iteration, color='gray', linestyle='--', label='Best iteration')
        ax.set(xlabel='Boosting iteration', ylabel=metric.upper(), title=f'Retention ratio {metric.upper()}')
        ax.legend(); ax.grid(alpha=.2)
    fig.tight_layout(); fig.savefig(outdir / 'learning_curves.png', dpi=140); plt.close(fig)
    table = pd.DataFrame(metrics['test_metrics']).T.to_html(float_format=lambda x: f'{x:.4f}')
    (outdir / 'report.html').write_text('''<!doctype html><html><meta charset="utf-8">
<title>From-scratch training report</title><style>body{font:16px system-ui;max-width:1100px;margin:40px auto;padding:20px;background:#f6f8fb;color:#182238}table{border-collapse:collapse;background:white}td,th{padding:12px;border:1px solid #ddd}img{width:100%}</style>
<h1>From-scratch CatBoost-style regression</h1>
<p>Independent NumPy/Pandas implementation. Ordered-prefix mode uses dyadic supporting models and shared tree structures; it is an approximation, not full CatBoost parity. Training curves are resubstitution metrics using inference encodings, not unbiased generalization estimates. Leaf fitting uses ordered encodings. Validation/test use training-only category maps.</p>
<h2>Held-out test results</h2>''' + table + f'<p>Boosting: {metrics["boosting"]}; permutations: {metrics["hyperparameters"]["permutations"]}; best iteration: {best_iteration}</p>'
        + '<h2>Training and validation progress</h2><img src="learning_curves.png" alt="Learning curves">'
        + '<p>Lower MAE/RMSE is better; higher R² is better. Ratio metrics and MYR price metrics use different units. Synthetic results do not establish real-market accuracy.</p>'
        + '<p><a href="learning_history.csv">Every-iteration CSV</a> · <a href="metrics.json">Full metrics</a> · <a href="feature_importance.csv">Feature split gains</a></p></html>', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', default=str(DATASET))
    parser.add_argument('--strategy', choices=['group', 'random'], default='group')
    parser.add_argument('--configuration', choices=['with_model', 'without_model'], default='with_model')
    parser.add_argument('--iterations', type=int, default=200)
    parser.add_argument('--depth', type=int, default=4)
    parser.add_argument('--bins', type=int, default=32)
    parser.add_argument('--learning-rate', type=float, default=.05)
    parser.add_argument('--patience', type=int, default=50)
    parser.add_argument('--boosting', choices=['ordered', 'plain'], default='ordered', help='Dyadic ordered-prefix supporting models or plain residuals')
    parser.add_argument('--permutations', type=int, default=3)
    parser.add_argument('--one-hot-max-size', type=int, default=4)
    parser.add_argument('--max-cat-combination', type=int, choices=[1, 2], default=2)
    parser.add_argument('--min-samples-leaf', type=int, default=5)
    parser.add_argument('--l2', type=float, default=3.)
    parser.add_argument('--min-gain', type=float, default=1e-8)
    parser.add_argument('--feature-fraction', type=float, default=1.)
    parser.add_argument('--bagging-temperature', type=float, default=0.)
    parser.add_argument('--log-every', type=int, default=1)
    parser.add_argument('--max-rows', type=int, help='Optional random sample for faster educational experiments')
    parser.add_argument('--output', type=Path, default=ROOT / 'scratch_runs')
    args = parser.parse_args()
    if args.log_every < 1 or (args.max_rows is not None and args.max_rows < 3):
        parser.error('log-every must be positive and max-rows must be at least 3')
    model = ScratchBoostRegressor(iterations=args.iterations, depth=args.depth, bins=args.bins,
                                  learning_rate=args.learning_rate, patience=args.patience,
                                  boosting=args.boosting, permutations=args.permutations,
                                  one_hot_max_size=args.one_hot_max_size, max_cat_combination=args.max_cat_combination,
                                  min_samples_leaf=args.min_samples_leaf, l2=args.l2, min_gain=args.min_gain,
                                  feature_fraction=args.feature_fraction, bagging_temperature=args.bagging_temperature)
    df, _ = load_data(args.data)
    if args.max_rows is not None and args.max_rows < len(df):
        df = df.sample(n=args.max_rows, random_state=42).reset_index(drop=True)
    splits = split_indices(df, args.strategy, 42)
    X, y = make_xy(df, args.configuration)
    tr, va, te = (splits[key] for key in ('train', 'validation', 'test'))
    # Unique run directories prevent overwriting earlier comparisons or library models.
    from datetime import datetime
    outdir = args.output / f'{args.strategy}_{args.configuration}_{datetime.now():%Y%m%d_%H%M%S_%f}'
    outdir.mkdir(parents=True)
    print(f'From-scratch trainer | {args.strategy}_{args.configuration} | {len(df):,} rows')
    print(f'Train: {len(tr):,} | Validation: {len(va):,} | Test: {len(te):,}')
    print(f'Retention-ratio metrics | boosting={args.boosting} | permutations={args.permutations}')
    print('Train metrics use inference encodings; validation determines early stopping.')
    print(' Iter | Train RMSE | Valid RMSE | Train MAE | Valid MAE | Train R2 | Valid R2 | Seconds')
    started = time.perf_counter()

    def progress(row):
        if row['iteration'] == 1 or row['iteration'] % args.log_every == 0:
            r2 = lambda value: '     n/a' if value is None else f'{value:8.4f}'
            print(f"{row['iteration']:5d} | {row['train_rmse']:10.6f} | {row['validation_rmse']:10.6f} | "
                  f"{row['train_mae']:9.6f} | {row['validation_mae']:9.6f} | "
                  f"{r2(row['train_r2'])} | {r2(row['validation_r2'])} | {time.perf_counter()-started:7.1f}", flush=True)

    model.fit(X.iloc[tr], y.iloc[tr], X.iloc[va], y.iloc[va], CATEGORICAL[args.configuration], progress)
    duration = time.perf_counter() - started
    prediction = model.predict(X.iloc[te])
    price = df.iloc[te].msrp.to_numpy() * np.clip(prediction, 0, .9999)
    metrics = {'implementation': 'scratch_boost_v2', 'boosting': args.boosting, 'categorical_encoding': 'permutation_aligned_ordered_statistics',
               'ordered_approximation': 'dyadic prefix leaf models; shared tree structures and quantile borders' if args.boosting == 'ordered' else None,
               'encoded_feature_count': len(model.specs), 'training_metric_encoding': 'inference (resubstitution)',
               'configuration': args.configuration, 'strategy': args.strategy, 'training_seconds': duration,
               'hyperparameters': model.params, 'dataset': str(Path(args.data).resolve()), 'sample_rows': len(df),
               'split': {key: {'records': len(idx), 'models': sorted(df.iloc[idx].model.unique().tolist())}
                         for key, idx in splits.items()},
               'best_iteration': model.best_iteration, 'attempted_iterations': len(model.history),
               'test_metrics': {'retention_ratio': regression_metrics(y.iloc[te], prediction),
                                'price_myr': regression_metrics(df.iloc[te].actualSoldPrice, price)}}
    model.save(outdir / 'model.json')
    model.feature_importance().to_csv(outdir / 'feature_importance.csv', index=False)
    save_report(pd.DataFrame(model.history), metrics, outdir, model.best_iteration)
    print('\nHeld-out test metrics:\n' + pd.DataFrame(metrics['test_metrics']).T.to_string(float_format=lambda x: f'{x:.4f}'))
    print(f'Best iteration: {model.best_iteration}; retained trees: {len(model.trees)}')
    print(f'Report: {(outdir / "report.html").resolve()}')


if __name__ == '__main__':
    main()
