"""CLI for the from-scratch educational trainer; no ML training libraries."""
import argparse
import json
import time
from pathlib import Path
import numpy as np
import pandas as pd
from .config import ROOT, CATEGORICAL
from .data_loader import load_data
from .preprocessing import make_xy, load_latest, DAMAGE_FIELDS
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
    is_xgb = metrics['implementation'] == 'scratch_xgboost_v1'
    title = 'XGBoost-style' if is_xgb else 'CatBoost-style'
    details = ('Independent NumPy/Pandas histogram boosting with second-order split gains, L1/L2 leaf penalties, '
               'gamma, asymmetric trees and learned missing-value directions. Categorical inputs use training-only one-hot encoding. '
               'This is a custom implementation of the core method, not the XGBoost package or its model format.' if is_xgb else
               'Independent NumPy/Pandas implementation. Ordered-prefix mode uses dyadic supporting models and shared tree structures; '
               'it is an approximation, not full CatBoost parity. Leaf fitting uses ordered encodings.')
    model_info = (f'Early stopping: {metrics["hyperparameters"]["early_stopping_metric"]}' if is_xgb else
                  f'Boosting: {metrics["boosting"]}; permutations: {metrics["hyperparameters"]["permutations"]}')
    checks_html = ''
    if 'depreciation_checks' in metrics:
        checks_html = ('<h2>Same-phone depreciation checks</h2>'
                       '<p>These checks measure whether predictions follow the expected direction and damage order.</p>'
                       + pd.DataFrame.from_dict(metrics['depreciation_checks'], orient='index').to_html()
                       + '<p><a href="depreciation_checks.csv">Scenario details</a></p>')
    if 'best_validation_price_mae_myr' in metrics:
        model_info += f' · Best validation price MAE: RM {metrics["best_validation_price_mae_myr"]:,.2f}'
    (outdir / 'report.html').write_text('''<!doctype html><html><meta charset="utf-8">
<title>From-scratch training report</title><style>body{font:16px system-ui;max-width:1100px;margin:40px auto;padding:20px;background:#f6f8fb;color:#182238}table{border-collapse:collapse;background:white}td,th{padding:12px;border:1px solid #ddd}img{width:100%}</style>
''' + f'<h1>From-scratch {title} regression</h1><p>{details}</p><p>Training curves are resubstitution metrics, not unbiased generalization estimates. All preprocessing is fitted on training data only.</p><h2>Held-out test results</h2>'
        + table + f'<p>{model_info}; best iteration: {best_iteration}</p>'
        + '<h2>Training and validation progress</h2><img src="learning_curves.png" alt="Learning curves">'
        + '<p>Lower MAE/RMSE is better; higher R² is better. Ratio metrics and MYR price metrics use different units. Synthetic results do not establish real-market accuracy.</p>'
        + checks_html + '<p><a href="learning_history.csv">Every-iteration CSV</a> · <a href="metrics.json">Full metrics</a> · <a href="feature_importance.csv">Feature split gains</a></p></html>', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', default=str(ROOT.parent / 'Phone Training Dataset - Temp Brand.csv'))
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
    if 'retentionRatio' in pd.read_csv(args.data, nrows=0).columns:
        df, X, y = load_latest(args.data, args.configuration)
    else:
        df, _ = load_data(args.data)
        X, y = make_xy(df, args.configuration)
    if args.max_rows is not None and args.max_rows < len(df):
        sample = df.sample(n=args.max_rows, random_state=42).index
        df, X, y = (part.loc[sample].reset_index(drop=True) for part in (df, X, y))
    splits = split_indices(df, args.strategy, 42)
    tr, va, te = (splits[key] for key in ('train', 'validation', 'test'))
    # Unique run directories prevent overwriting earlier comparisons or library models.
    from datetime import datetime
    outdir = args.output / f'{args.strategy}_{args.configuration}_{datetime.now():%Y%m%d_%H%M%S_%f}'
    outdir.mkdir(parents=True)
    print(f'From-scratch trainer | {args.strategy}_{args.configuration} | {len(df):,} rows')
    print(f'Train: {len(tr):,} | Validation: {len(va):,} | Test: {len(te):,}')
    print(f'Retention-ratio metrics | boosting={args.boosting} | permutations={args.permutations}')
    print(f'Early stopping uses validation price MAE in MYR (patience: {args.patience}).')
    print(' Iter | Train RMSE | Valid RMSE | Train MAE | Valid MAE | Train R2 | Valid R2 | Price MAE (RM) | Seconds')
    started = time.perf_counter()

    def progress(row):
        if row['iteration'] == 1 or row['iteration'] % args.log_every == 0:
            r2 = lambda value: '     n/a' if value is None else f'{value:8.4f}'
            print(f"{row['iteration']:5d} | {row['train_rmse']:10.6f} | {row['validation_rmse']:10.6f} | "
                  f"{row['train_mae']:9.6f} | {row['validation_mae']:9.6f} | "
                  f"{r2(row['train_r2'])} | {r2(row['validation_r2'])} | "
                  f"{row['validation_price_mae']:14.2f} | {time.perf_counter()-started:7.1f}", flush=True)

    model.fit(X.iloc[tr], y.iloc[tr], X.iloc[va], y.iloc[va], CATEGORICAL[args.configuration], progress,
              validation_msrp=df.iloc[va].msrp, validation_price=df.iloc[va].actualSoldPrice)
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
               'selection_metric': model.selection_metric,
               'best_validation_price_mae_myr': model.history[model.best_iteration - 1]['validation_price_mae'],
               'test_metrics': {'retention_ratio': regression_metrics(y.iloc[te], prediction),
                                'price_myr': regression_metrics(df.iloc[te].actualSoldPrice, price)}}
    model.save(outdir / 'model.json')
    model.feature_importance().to_csv(outdir / 'feature_importance.csv', index=False)
    if set(DAMAGE_FIELDS).issubset(X.columns):
        checks = depreciation_checks(model, X.iloc[va])
        checks.to_csv(outdir / 'depreciation_checks.csv', index=False)
        summary = checks.groupby('check').passed.agg(['sum', 'count'])
        summary.columns = ['Passed', 'Checked']
        metrics['depreciation_checks'] = summary.to_dict('index')
        print('\nSame-phone checks on validation profiles:\n' + summary.to_string())
    save_report(pd.DataFrame(model.history), metrics, outdir, model.best_iteration)
    print('\nHeld-out test metrics:\n' + pd.DataFrame(metrics['test_metrics']).T.to_string(float_format=lambda x: f'{x:.4f}'))
    print(f'Best iteration: {model.best_iteration}; retained trees: {len(model.trees)}')
    print(f'Report: {(outdir / "report.html").resolve()}')


def depreciation_checks(model, profiles):
    """Change one feature per scenario on one profile per phone variant."""
    keys = [col for col in ('brand', 'model', 'ramCapacity', 'storage', 'msrp') if col in profiles]
    base = profiles.drop_duplicates(keys).reset_index(drop=True)
    cases = []
    factors = {'deviceAge': range(11), 'internalPerfromanceOverallMark': range(0, 101, 10)}
    factors.update({field: range(0, 101, 10) for field in DAMAGE_FIELDS})
    for field, values in factors.items():
        for value in values:
            scenario = base.copy()
            if field in DAMAGE_FIELDS:
                scenario[list(DAMAGE_FIELDS)] = 0
            scenario[field] = value
            cases.append((field, value, scenario))
    inputs = pd.concat([scenario for _, _, scenario in cases], ignore_index=True)
    prices = inputs.msrp.to_numpy() * np.clip(model.predict(inputs), 0, .9999)
    curves = {field: {} for field in factors}
    for index, (field, value, _) in enumerate(cases):
        curves[field][value] = prices[index*len(base):(index+1)*len(base)]
    comparisons = []
    for field, curve in curves.items():
        levels = list(curve)
        for low, high in zip(levels, levels[1:]):
            change = curve[high] - curve[low]
            passed = change >= -.005 if field == 'internalPerfromanceOverallMark' else change <= .005
            comparisons.append(base[keys].assign(check=field, low=low, high=high,
                                                price_before=curve[low], price_after=curve[high],
                                                change_myr=change, passed=passed))
    for first, second in zip(DAMAGE_FIELDS, DAMAGE_FIELDS[1:]):
        for score in range(10, 101, 10):
            first_drop = curves[first][0] - curves[first][score]
            second_drop = curves[second][0] - curves[second][score]
            comparisons.append(base[keys].assign(check=f'{first} > {second}', low=0, high=score,
                                                price_before=curves[second][score], price_after=curves[first][score],
                                                change_myr=second_drop-first_drop,
                                                passed=(first_drop-second_drop) > .005))
    return pd.concat(comparisons, ignore_index=True)


if __name__ == '__main__':
    # Keep this familiar entry point, with XGBoost-style training now the default.
    import sys
    selector = argparse.ArgumentParser(add_help=False)
    selector.add_argument('--algorithm', choices=['xgboost', 'catboost'], default='xgboost')
    selected, remaining = selector.parse_known_args()
    sys.argv[1:] = remaining
    if selected.algorithm == 'catboost':
        main()
    else:
        from .train_xgboost import main as xgboost_main
        xgboost_main()
