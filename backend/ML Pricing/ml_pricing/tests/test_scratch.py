import tempfile
import unittest
from pathlib import Path
import numpy as np
import pandas as pd
from ml_pricing.src.scratch import ScratchBoostRegressor, _PrefixState
from ml_pricing.src.train_scratch import split_indices


class ScratchTests(unittest.TestCase):
    def test_learns_numeric_signal_and_roundtrips(self):
        rng = np.random.default_rng(1)
        X = pd.DataFrame({'x': rng.uniform(size=400), 'brand': ['a', 'b'] * 200})
        y = .1 + .7 * X.x.to_numpy()
        model = ScratchBoostRegressor(iterations=50, depth=3, learning_rate=.15)
        model.fit(X.iloc[:300], y[:300], X.iloc[300:], y[300:], ['brand'])
        pred = model.predict(X.iloc[300:])
        self.assertLess(np.mean((pred-y[300:])**2), .1*np.mean((y[300:]-y[:300].mean())**2))
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as directory:
            path = Path(directory)/'model.json'; model.save(path)
            np.testing.assert_allclose(pred, ScratchBoostRegressor.load(path).predict(X.iloc[300:]))
        unseen = pd.DataFrame({'x': [.5], 'brand': ['new']})
        self.assertTrue(np.isfinite(model.predict(unseen)).all())

    def test_ordered_encoding_excludes_own_target(self):
        X = pd.DataFrame({'cat': ['a', 'b', 'c', 'd']})
        model = ScratchBoostRegressor(bins=4, one_hot_max_size=0)
        binned = model._encode_fit(X, np.array([.1, .2, .8, .9]), ['cat'])
        # Every category appears once, so every training encoding is the fixed prior.
        targets = [i for i, spec in enumerate(model.specs) if spec['kind'] == 'target']
        for i in targets:
            self.assertEqual(len(np.unique(binned[:, i])), 1)
            self.assertEqual(model.borders[i], [.25])

    def test_validation_targets_do_not_change_tree_updates(self):
        X = pd.DataFrame({'x': np.linspace(0, 1, 60)})
        y = X.x.to_numpy()
        a, b = (ScratchBoostRegressor(iterations=1) for _ in range(2))
        a.fit(X, y, X, y)
        b.fit(X, y, X, 1-y)
        self.assertEqual(a.trees, b.trees)

    def test_group_split_has_no_overlap(self):
        df = pd.DataFrame({'model': np.repeat(list('abcdefghij'), 5)})
        parts = split_indices(df, 'group', 42)
        groups = [set(df.iloc[idx].model) for idx in parts.values()]
        self.assertFalse(groups[0] & groups[1] or groups[0] & groups[2] or groups[1] & groups[2])
        self.assertEqual(len(set(np.concatenate(list(parts.values())))), len(df))

    def test_early_stopping_retains_best_prefix(self):
        X = pd.DataFrame({'x': np.linspace(0, 1, 80)})
        model = ScratchBoostRegressor(iterations=30, patience=2)
        model.fit(X, X.x, X, 1-X.x)
        self.assertLess(len(model.history), 30)
        self.assertEqual(len(model.trees), model.best_iteration)
        self.assertEqual(model.best_iteration, 1 + np.argmin([r['validation_rmse'] for r in model.history]))

    def test_prefix_updates_match_independent_brute_force_models(self):
        binned = np.array([[0], [1], [0], [1], [0], [1], [0], [1]], dtype=np.uint8)
        y = np.array([.1, .9, .2, .8, .3, .7, .4, .6])
        state = _PrefixState(binned, y, np.arange(8), .25)
        expected = {p: np.full(8, .25) for p in (1, 2, 4)}
        splits = [(0, 0)]
        for _ in range(3):
            state.update(splits, .1, 2.)
            for p, pred in expected.items():
                leaf_means = []
                for leaf in (0, 1):
                    selected = np.flatnonzero(binned[:p, 0] == leaf)
                    leaf_means.append(np.sum(y[selected]-pred[selected])/(len(selected)+2.))
                pred += .1*np.array(leaf_means)[binned[:, 0]]
            expected_prediction = np.full(8, .25)
            for p in (1, 2, 4):
                expected_prediction[p:2*p] = expected[p][p:2*p]
            np.testing.assert_allclose(state.residuals(), y-expected_prediction)

    def test_prefix_leaf_updates_cannot_see_current_or_future_targets(self):
        binned = np.zeros((8, 1), dtype=np.uint8)
        y = np.arange(8.)/8
        altered = y.copy(); altered[4:] += 100
        a = _PrefixState(binned, y, np.arange(8), .25)
        b = _PrefixState(binned, altered, np.arange(8), .25)
        for _ in range(4):
            a.update([], .1, 3); b.update([], .1, 3)
        # For a fixed shared structure, the prefix-4 predictor never fits rows 4+.
        np.testing.assert_allclose(a.prefixes[-1][1], b.prefixes[-1][1])

    def test_category_pairs_do_not_collide_and_unseen_fallback_is_finite(self):
        X = pd.DataFrame({'a': ['a|b', 'a']*10, 'b': ['c', 'b|c']*10})
        model = ScratchBoostRegressor(iterations=3, one_hot_max_size=0)
        model.fit(X, np.linspace(0, 1, 20), X, np.linspace(0, 1, 20), ['a', 'b'])
        pairs = [stats for key, stats in model.category_maps.items() if len(__import__('json').loads(key)) == 2]
        self.assertEqual(len(pairs[0]['count']), 2)
        self.assertTrue(np.isfinite(model.predict(pd.DataFrame({'a': ['new'], 'b': ['new']}))).all())

    def test_splits_respect_minimum_occupied_leaf_size(self):
        X = pd.DataFrame({'x': np.arange(100.)})
        model = ScratchBoostRegressor(iterations=1, depth=5, min_samples_leaf=12, permutations=1)
        model.fit(X, np.arange(100.)/100, X, np.arange(100.)/100)
        ids = model._leaf_ids(model._transform(X), model.trees[0]['splits'])
        sizes = np.bincount(ids)
        self.assertTrue((sizes[sizes > 0] >= 12).all())

    def test_permutations_bootstrap_and_feature_sampling_are_reproducible(self):
        X = pd.DataFrame({'x': np.linspace(0, 1, 120), 'c': np.tile(['a', 'b', 'c'], 40)})
        y = .2 + .5*X.x.to_numpy()
        models = [ScratchBoostRegressor(iterations=12, bagging_temperature=1., feature_fraction=.7) for _ in range(2)]
        for model in models:
            model.fit(X, y, X, y, ['c'])
        self.assertEqual(models[0].trees, models[1].trees)
        self.assertGreater(len({row['permutation'] for row in models[0].history}), 1)
        np.testing.assert_allclose(models[0].predict(X), models[1].predict(X))

    def test_ordered_target_values_do_not_use_later_labels(self):
        X = pd.DataFrame({'c': ['same']*20})
        y = np.linspace(.1, .9, 20)
        model = ScratchBoostRegressor(one_hot_max_size=0)
        model._encode_fit(X, y, ['c'])
        order = model._orders[0]
        before = model._matrix(X, y, order)
        changed = y.copy(); changed[order[10:]] += 10
        after = model._matrix(X, changed, order)
        np.testing.assert_allclose(before[order[:11]], after[order[:11]])

    def test_legacy_v1_model_can_still_be_loaded(self):
        from ml_pricing.src.scratch import _PlainV1Regressor
        X = pd.DataFrame({'x': np.linspace(0, 1, 30)})
        old = _PlainV1Regressor(iterations=2)
        old.fit(X, X.x, X, X.x)
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as directory:
            path = Path(directory)/'legacy.json'; old.save(path)
            np.testing.assert_allclose(old.predict(X), ScratchBoostRegressor.load(path).predict(X))

    def test_categorical_pair_learns_interaction_without_numeric_features(self):
        rng = np.random.default_rng(12)
        a, b = rng.integers(0, 2, size=(2, 1000))
        X = pd.DataFrame({'a': a.astype(str), 'b': b.astype(str)})
        y = np.where(a == b, .8, .2)
        model = ScratchBoostRegressor(iterations=60, depth=1, learning_rate=.15, one_hot_max_size=0)
        model.fit(X.iloc[:800], y[:800], X.iloc[800:], y[800:], ['a', 'b'])
        self.assertLess(np.mean(np.abs(model.predict(X.iloc[800:])-y[800:])), .05)
        importance = model.feature_importance()
        self.assertTrue(importance.loc[importance.feature.str.contains('"a", "b"'), 'split_gain_percent'].sum() > 0)

    def test_training_metrics_match_saved_ensemble_when_final_iteration_is_best(self):
        from ml_pricing.src.scratch import regression_metrics
        X = pd.DataFrame({'x': np.linspace(0, 1, 120), 'c': np.tile(['a', 'b', 'c'], 40)})
        y = .2+.5*X.x.to_numpy()
        model = ScratchBoostRegressor(iterations=4)
        model.fit(X, y, X, y, ['c'])
        self.assertEqual(model.best_iteration, 4)
        self.assertAlmostEqual(model.history[-1]['train_rmse'], regression_metrics(y, model.predict(X))['rmse'])


if __name__ == '__main__':
    unittest.main()
