"""Educational CatBoost-style regression, implemented with NumPy/Pandas only.

Includes a legacy plain trainer and an enhanced permutation/prefix trainer.
This is an independent educational implementation, not binary-compatible CatBoost.
"""
import json
from pathlib import Path
import numpy as np
import pandas as pd


def regression_metrics(y, prediction):
    y, prediction = np.asarray(y, dtype=float), np.asarray(prediction, dtype=float)
    error = prediction - y
    total = np.sum((y - y.mean()) ** 2)
    return {"mae": float(np.mean(np.abs(error))),
            "rmse": float(np.sqrt(np.mean(error ** 2))),
            "r2": float(1 - np.sum(error ** 2) / total) if total > 0 else None}


class _PlainV1Regressor:
    def __init__(self, iterations=200, depth=4, learning_rate=.05, bins=32,
                 l2=3., patience=50, seed=42, prior=.25, smoothing=10.):
        if iterations < 1 or not 1 <= depth <= 10 or not 2 <= bins <= 255:
            raise ValueError("Require iterations>=1, depth in 1..10, bins in 2..255")
        if not 0 < learning_rate <= 1 or l2 < 0 or patience < 1 or smoothing <= 0:
            raise ValueError("Invalid learning rate, regularization, patience, or smoothing")
        self.params = dict(iterations=iterations, depth=depth, learning_rate=learning_rate,
                           bins=bins, l2=l2, patience=patience, seed=seed,
                           prior=prior, smoothing=smoothing)

    def _encode_fit(self, X, y, categorical):
        self.features = list(X.columns)
        self.categorical = list(categorical)
        self.category_maps = {}
        values = X.copy()
        order = np.random.default_rng(self.params['seed']).permutation(len(X))
        alpha, prior = self.params['smoothing'], self.params['prior']
        for col in categorical:
            keys = X[col].fillna('__UNKNOWN__').astype(str).str.strip().str.casefold()
            ordered = pd.DataFrame({'key': keys.to_numpy()[order], 'y': y[order]})
            groups = ordered.groupby('key', sort=False)
            # A row's encoded value uses preceding targets only, never its own.
            encoded = (groups.y.cumsum().to_numpy() - ordered.y.to_numpy() + alpha * prior)
            encoded /= groups.cumcount().to_numpy() + alpha
            restored = np.empty(len(y)); restored[order] = encoded
            values[col] = restored
            summary = ordered.groupby('key').y.agg(['sum', 'count'])
            self.category_maps[col] = ((summary['sum'] + alpha * prior) / (summary['count'] + alpha)).to_dict()
        matrix = values.to_numpy(dtype=float)
        if not np.isfinite(matrix).all():
            raise ValueError('Features must be finite numbers after categorical encoding')
        self.borders = [np.unique(np.quantile(matrix[:, j], np.linspace(0, 1, self.params['bins'] + 1)[1:-1])).tolist()
                        for j in range(matrix.shape[1])]
        return self._bin(matrix)

    def _bin(self, matrix):
        return np.column_stack([np.searchsorted(edges, matrix[:, j], side='left')
                                for j, edges in enumerate(self.borders)]).astype(np.uint8)

    def _transform(self, X):
        values = X.loc[:, self.features].copy()
        for col in self.categorical:
            keys = values[col].fillna('__UNKNOWN__').astype(str).str.strip().str.casefold()
            values[col] = keys.map(self.category_maps[col]).fillna(self.params['prior'])
        matrix = values.to_numpy(dtype=float)
        if not np.isfinite(matrix).all():
            raise ValueError('Features must be finite numbers after categorical encoding')
        return self._bin(matrix)

    @staticmethod
    def _leaf_ids(binned, splits):
        ids = np.zeros(len(binned), dtype=np.int32)
        for feature, threshold in splits:
            ids = ids * 2 + (binned[:, feature] > threshold)
        return ids

    def _tree(self, binned, residual):
        ids = np.zeros(len(binned), dtype=np.int32)
        splits = []
        l2 = self.params['l2']
        for level in range(self.params['depth']):
            leaves = 2 ** level
            counts = np.bincount(ids, minlength=leaves)
            sums = np.bincount(ids, weights=residual, minlength=leaves)
            parent = np.sum(sums ** 2 / np.maximum(counts + l2, 1e-12))
            best_gain, best = 1e-12, None
            for feature, edges in enumerate(self.borders):
                width = len(edges) + 1
                if width < 2:
                    continue
                cell = ids * width + binned[:, feature]
                count = np.bincount(cell, minlength=leaves * width).reshape(leaves, width)
                total = np.bincount(cell, weights=residual, minlength=leaves * width).reshape(leaves, width)
                left_n, left_s = count.cumsum(axis=1)[:, :-1], total.cumsum(axis=1)[:, :-1]
                right_n, right_s = counts[:, None] - left_n, sums[:, None] - left_s
                gains = np.sum(left_s ** 2 / np.maximum(left_n + l2, 1e-12)
                               + right_s ** 2 / np.maximum(right_n + l2, 1e-12), axis=0) - parent
                threshold = int(np.argmax(gains))
                if gains[threshold] > best_gain:
                    best_gain, best = gains[threshold], (feature, threshold)
            if best is None:
                break
            splits.append(best)
            ids = ids * 2 + (binned[:, best[0]] > best[1])
        counts = np.bincount(ids, minlength=2 ** len(splits))
        sums = np.bincount(ids, weights=residual, minlength=len(counts))
        leaf_values = sums / np.maximum(counts + l2, 1e-12)
        return {'splits': splits, 'values': leaf_values.tolist()}, leaf_values[ids]

    def fit(self, X, y, X_valid, y_valid, categorical=(), callback=None):
        y, y_valid = np.asarray(y, dtype=float), np.asarray(y_valid, dtype=float)
        if len(y) != len(X) or len(y_valid) != len(X_valid) or not len(y) or not len(y_valid):
            raise ValueError('Nonempty, matching train and validation arrays required')
        if not np.isfinite(y).all() or not np.isfinite(y_valid).all():
            raise ValueError('Targets must be finite')
        train = self._encode_fit(X, y, categorical)
        valid = self._transform(X_valid)
        self.base = float(y.mean())
        train_pred, valid_pred = np.full(len(y), self.base), np.full(len(y_valid), self.base)
        self.trees, self.history = [], []
        best, stale, self.best_iteration = float('inf'), 0, 0
        for iteration in range(1, self.params['iterations'] + 1):
            tree, update = self._tree(train, y - train_pred)
            self.trees.append(tree)
            train_pred += self.params['learning_rate'] * update
            valid_pred += self.params['learning_rate'] * np.asarray(tree['values'])[self._leaf_ids(valid, tree['splits'])]
            row = {'iteration': iteration}
            for split, truth, prediction in [('train', y, train_pred), ('validation', y_valid, valid_pred)]:
                row.update({f'{split}_{k}': v for k, v in regression_metrics(truth, prediction).items()})
            self.history.append(row)
            if row['validation_rmse'] < best - 1e-12:
                best, stale, self.best_iteration = row['validation_rmse'], 0, iteration
            else:
                stale += 1
            if callback:
                callback(row)
            if stale >= self.params['patience']:
                break
        self.trees = self.trees[:self.best_iteration]
        return self

    def predict(self, X):
        binned = self._transform(X)
        prediction = np.full(len(X), self.base)
        for tree in self.trees:
            prediction += self.params['learning_rate'] * np.asarray(tree['values'])[self._leaf_ids(binned, tree['splits'])]
        return prediction

    def save(self, path):
        state = {name: getattr(self, name) for name in
                 ('params', 'features', 'categorical', 'category_maps', 'borders', 'base', 'trees', 'best_iteration')}
        Path(path).write_text(json.dumps({'format': 'scratch_boost_v1', **state}, allow_nan=False), encoding='utf-8')

    @classmethod
    def load(cls, path):
        state = json.loads(Path(path).read_text(encoding='utf-8'))
        if state.pop('format') != 'scratch_boost_v1':
            raise ValueError('Unsupported model format')
        model = cls(**state['params'])
        model.__dict__.update(state)
        return model


class _PrefixState:
    """Supporting models for dyadic prefixes in one fixed permutation.

    Prefix p predicts rows [0, min(2p,n)); only [0,p) supplies its leaf targets.
    Thus the model used for the next block never fits leaf values to that block.
    Tree structures and quantization are shared, an explicit approximation.
    """
    def __init__(self, binned, y, order, prior):
        self.order = order
        self.binned, self.y = binned[order], y[order]
        self.prior = prior
        self.prefixes = []
        p = 1
        while p < len(y):
            self.prefixes.append((p, np.full(min(2*p, len(y)), prior)))
            p *= 2

    def residuals(self):
        prediction = np.full(len(self.y), self.prior)
        for p, values in self.prefixes:
            prediction[p:len(values)] = values[p:]
        result = np.empty(len(self.y))
        result[self.order] = self.y - prediction
        return result

    def update(self, splits, learning_rate, l2):
        ids = _PlainV1Regressor._leaf_ids(self.binned, splits)
        for p, prediction in self.prefixes:
            count = np.bincount(ids[:p], minlength=2 ** len(splits))
            sums = np.bincount(ids[:p], weights=self.y[:p]-prediction[:p], minlength=len(count))
            leaves = sums / np.maximum(count + l2, 1e-12)
            prediction += learning_rate * leaves[ids[:len(prediction)]]


class ScratchBoostRegressor(_PlainV1Regressor):
    """Symmetric trees with ordered-prefix or plain boosting, without ML libraries.

    Ordered-prefix mode uses dyadic supporting models, multiple aligned encoding/
    boosting permutations, and shared tree structures. It is not exact per-row
    prefix CatBoost: split structures and quantile borders see all training rows.
    """
    def __init__(self, iterations=200, depth=4, learning_rate=.05, bins=32,
                 l2=3., patience=50, seed=42, prior=.25, smoothing=10.,
                 boosting='ordered', permutations=3, one_hot_max_size=4,
                 max_cat_combination=2, min_samples_leaf=5, min_gain=1e-8,
                 feature_fraction=1., bagging_temperature=0.):
        super().__init__(iterations, depth, learning_rate, bins, l2, patience, seed, prior, smoothing)
        if boosting not in ('ordered', 'plain') or permutations < 1:
            raise ValueError('Require boosting ordered/plain and permutations>=1')
        if not 0 <= one_hot_max_size <= 32 or max_cat_combination not in (1, 2):
            raise ValueError('Require one_hot_max_size in 0..32 and max_cat_combination in 1..2')
        if min_samples_leaf < 1 or min_gain < 0 or not 0 < feature_fraction <= 1 or bagging_temperature < 0:
            raise ValueError('Invalid leaf size, gain, feature fraction, or bagging temperature')
        if not np.isfinite([learning_rate, l2, prior, smoothing, min_gain, feature_fraction, bagging_temperature]).all():
            raise ValueError('Hyperparameters must be finite')
        self.params.update(boosting=boosting, permutations=permutations,
                           one_hot_max_size=one_hot_max_size, max_cat_combination=max_cat_combination,
                           min_samples_leaf=min_samples_leaf, min_gain=min_gain,
                           feature_fraction=feature_fraction, bagging_temperature=bagging_temperature)

    @staticmethod
    def _category_keys(X, columns):
        normalized = [X[col].fillna('__UNKNOWN__').astype(str).str.strip().str.casefold().to_numpy()
                      for col in columns]
        # JSON tuples prevent collisions such as ('a|b','c') and ('a','b|c').
        return pd.Series([json.dumps(items, ensure_ascii=False) for items in zip(*normalized)])

    def _build_specs(self, X, y, categorical):
        from itertools import combinations
        self.features, self.categorical = list(X.columns), list(categorical)
        if not self.features or len(set(self.features)) != len(self.features):
            raise ValueError('Feature columns must be nonempty and unique')
        if not set(categorical).issubset(self.features):
            raise ValueError('Categorical columns must be feature columns')
        groups = [(col,) for col in categorical]
        if self.params['max_cat_combination'] == 2:
            if len(categorical) > 8:
                raise ValueError('Pair combinations limited to 8 categorical columns; set max_cat_combination=1')
            groups += list(combinations(categorical, 2))
        self.specs = [{'kind': 'numeric', 'columns': [col], 'name': col}
                      for col in self.features if col not in categorical]
        self.category_maps = {}
        for columns in groups:
            keys = self._category_keys(X, columns)
            name = json.dumps(columns)
            summary = pd.DataFrame({'key': keys, 'y': y}).groupby('key').y.agg(['sum', 'count'])
            self.category_maps[name] = {'sum': summary['sum'].to_dict(), 'count': summary['count'].to_dict(), 'n': len(y)}
            categories = sorted(summary.index.tolist())
            common = {'columns': list(columns), 'group': name}
            if len(categories) <= self.params['one_hot_max_size']:
                for category in categories:
                    self.specs.append({**common, 'kind': 'onehot', 'category': category,
                                       'name': f'{name}=={category}'})
            else:
                # Two smoothing strengths express uncertainty for rare categories.
                for alpha in (self.params['smoothing'], self.params['smoothing'] * 5):
                    self.specs.append({**common, 'kind': 'target', 'alpha': alpha,
                                       'name': f'{name}:target_mean:{alpha}'})
            self.specs.append({**common, 'kind': 'frequency', 'name': f'{name}:frequency'})
        self.encoded_feature_names = [spec['name'] for spec in self.specs]

    def _matrix(self, X, y=None, order=None):
        cache, columns = {}, []
        for spec in self.specs:
            kind = spec['kind']
            if kind == 'numeric':
                columns.append(X[spec['columns'][0]].to_numpy(dtype=float))
                continue
            group = spec['group']
            if group not in cache:
                keys = self._category_keys(X, spec['columns'])
                stats = self.category_maps[group]
                cache[group] = {'keys': keys, 'sum': keys.map(stats['sum']).fillna(0).to_numpy(),
                                'count': keys.map(stats['count']).fillna(0).to_numpy(), 'n': stats['n']}
                if y is not None:
                    ordered = pd.DataFrame({'key': keys.to_numpy()[order], 'y': y[order]})
                    groups = ordered.groupby('key', sort=False)
                    before_sum = groups.y.cumsum().to_numpy() - ordered.y.to_numpy()
                    before_count = groups.cumcount().to_numpy()
                    sums, counts = np.empty(len(y)), np.empty(len(y))
                    sums[order], counts[order] = before_sum, before_count
                    cache[group].update(ordered_sum=sums, ordered_count=counts)
            cached = cache[group]
            if kind == 'onehot':
                values = (cached['keys'] == spec['category']).to_numpy(dtype=float)
            elif kind == 'frequency':
                # Target-free counts fitted on training X only.
                values = cached['count'] / cached['n']
            else:
                sums = cached['ordered_sum'] if y is not None else cached['sum']
                counts = cached['ordered_count'] if y is not None else cached['count']
                values = (sums + spec['alpha'] * self.params['prior']) / (counts + spec['alpha'])
            columns.append(values)
        matrix = np.column_stack(columns)
        if not np.isfinite(matrix).all():
            raise ValueError('Features must be finite after encoding')
        return matrix

    def _encode_fit(self, X, y, categorical):
        self._build_specs(X, y, categorical)
        rng = np.random.default_rng(self.params['seed'])
        self._orders = [rng.permutation(len(y)) for _ in range(self.params['permutations'])]
        first = self._matrix(X, y, self._orders[0])
        self.borders = [np.unique(np.quantile(first[:, j], np.linspace(0, 1, self.params['bins'] + 1)[1:-1])).tolist()
                        for j in range(first.shape[1])]
        return self._bin(first)

    def _transform(self, X):
        return self._bin(self._matrix(X.loc[:, self.features]))

    def _tree(self, binned, residual, weights=None, rng=None):
        """Choose one regularized histogram split per depth across all leaves."""
        if weights is None:
            weights = np.ones(len(residual))
        if rng is None:
            rng = np.random.default_rng(self.params['seed'])
        ids = np.zeros(len(binned), dtype=np.int32)
        splits, split_gains = [], []
        l2 = self.params['l2']
        for level in range(self.params['depth']):
            leaves = 2 ** level
            counts = np.bincount(ids, weights=weights, minlength=leaves)
            sums = np.bincount(ids, weights=residual * weights, minlength=leaves)
            parent = np.sum(sums ** 2 / np.maximum(counts + l2, 1e-12))
            best_gain, best = self.params['min_gain'], None
            eligible = np.arange(binned.shape[1])
            if self.params['feature_fraction'] < 1:
                eligible = rng.choice(eligible, max(1, int(np.ceil(len(eligible)*self.params['feature_fraction']))), replace=False)
            for feature in eligible:
                width = len(self.borders[feature]) + 1
                if width < 2:
                    continue
                cell = ids * width + binned[:, feature]
                count = np.bincount(cell, weights=weights, minlength=leaves*width).reshape(leaves, width)
                total = np.bincount(cell, weights=residual*weights, minlength=leaves*width).reshape(leaves, width)
                raw = np.bincount(cell, weights=(weights > 0), minlength=leaves*width).reshape(leaves, width)
                ln, ls = count.cumsum(axis=1)[:, :-1], total.cumsum(axis=1)[:, :-1]
                rn, rs = counts[:, None]-ln, sums[:, None]-ls
                lr = raw.cumsum(axis=1)[:, :-1]; rr = raw.sum(axis=1)[:, None]-lr
                # Empty children are allowed in an oblivious tree; tiny occupied leaves are not.
                invalid = np.any(((lr > 0) & (lr < self.params['min_samples_leaf']))
                                 | ((rr > 0) & (rr < self.params['min_samples_leaf'])), axis=0)
                gains = np.sum(ls**2/np.maximum(ln+l2, 1e-12) + rs**2/np.maximum(rn+l2, 1e-12), axis=0)-parent
                gains[invalid] = -np.inf
                threshold = int(np.argmax(gains))
                if gains[threshold] > best_gain:
                    best_gain, best = float(gains[threshold]), (int(feature), threshold)
            if best is None:
                break
            splits.append(best); split_gains.append(best_gain)
            ids = ids*2 + (binned[:, best[0]] > best[1])
        values = self._fit_leaves(ids, residual, len(splits), weights)
        return {'splits': splits, 'values': values.tolist(), 'split_gains': split_gains}, values[ids]

    def _fit_leaves(self, ids, residual, depth, weights=None):
        counts = np.bincount(ids, weights=weights, minlength=2**depth)
        sums = np.bincount(ids, weights=residual if weights is None else residual*weights, minlength=len(counts))
        return sums/np.maximum(counts+self.params['l2'], 1e-12)

    def fit(self, X, y, X_valid, y_valid, categorical=(), callback=None):
        y, y_valid = np.asarray(y, dtype=float), np.asarray(y_valid, dtype=float)
        if y.ndim != 1 or y_valid.ndim != 1 or len(y) != len(X) or len(y_valid) != len(X_valid) or len(y) < 2 or not len(y_valid):
            raise ValueError('Require at least 2 training rows and nonempty matching validation arrays')
        if not np.isfinite(y).all() or not np.isfinite(y_valid).all():
            raise ValueError('Targets must be finite')
        first = self._encode_fit(X, y, categorical)
        matrices = [first] + [self._bin(self._matrix(X, y, order)) for order in self._orders[1:]]
        inference, valid = self._transform(X), self._transform(X_valid)
        ordered = self.params['boosting'] == 'ordered'
        # A fixed prior avoids a global mean leaking later labels into prefix models.
        self.base = self.params['prior'] if ordered else float(y.mean())
        train_pred, valid_pred = np.full(len(y), self.base), np.full(len(y_valid), self.base)
        plain_predictions = [np.full(len(y), self.base) for _ in matrices]
        states = [_PrefixState(matrix, y, order, self.base) for matrix, order in zip(matrices, self._orders)] if ordered else []
        self.trees, self.history = [], []
        self.best_iteration, best, stale = 0, float('inf'), 0
        rng = np.random.default_rng(self.params['seed'] + 1)
        for iteration in range(1, self.params['iterations'] + 1):
            permutation = int(rng.integers(len(matrices)))
            residual = states[permutation].residuals() if ordered else y-plain_predictions[permutation]
            weights = np.ones(len(y))
            if self.params['bagging_temperature']:
                weights = rng.exponential(size=len(y)) ** self.params['bagging_temperature']
            if ordered:
                weights[self._orders[permutation][0]] = 0
            tree, _ = self._tree(matrices[permutation], residual, weights, rng)
            # Fit deployment leaf values on ordered encodings, not own-target maps.
            # Each permutation tracks this same ensemble on its training encodings.
            fit_ids = self._leaf_ids(matrices[permutation], tree['splits'])
            values = self._fit_leaves(fit_ids, y-plain_predictions[permutation], len(tree['splits']))
            full_ids = self._leaf_ids(inference, tree['splits'])
            tree.update(values=values.tolist(), permutation=permutation)
            self.trees.append(tree)
            rate = self.params['learning_rate']
            train_pred += rate*values[full_ids]
            valid_pred += rate*values[self._leaf_ids(valid, tree['splits'])]
            if ordered:
                for state in states:
                    state.update(tree['splits'], rate, self.params['l2'])
            for matrix, prediction in zip(matrices, plain_predictions):
                ids = self._leaf_ids(matrix, tree['splits'])
                prediction += rate*values[ids]
            row = {'iteration': iteration, 'permutation': permutation, 'tree_depth': len(tree['splits'])}
            for split, truth, prediction in [('train', y, train_pred), ('validation', y_valid, valid_pred)]:
                row.update({f'{split}_{k}': v for k, v in regression_metrics(truth, prediction).items()})
            if ordered:
                # This diagnostic uses prefix predictions, excluding the no-history first row.
                residual = states[permutation].residuals()
                mask = np.ones(len(y), dtype=bool); mask[self._orders[permutation][0]] = False
                row['ordered_prefix_rmse'] = float(np.sqrt(np.mean(residual[mask]**2)))
            self.history.append(row)
            if row['validation_rmse'] < best - 1e-12:
                self.best_iteration, best, stale = iteration, row['validation_rmse'], 0
            else:
                stale += 1
            if callback:
                callback(row)
            if stale >= self.params['patience']:
                break
        self.trees = self.trees[:self.best_iteration]
        return self

    def feature_importance(self):
        gains = np.zeros(len(self.specs))
        for tree in self.trees:
            for (feature, _), gain in zip(tree['splits'], tree['split_gains']):
                gains[feature] += gain
        total = gains.sum()
        return pd.DataFrame({'feature': self.encoded_feature_names,
                             'split_gain_percent': gains*100/total if total else gains}).sort_values('split_gain_percent', ascending=False)

    def save(self, path):
        state = {name: getattr(self, name) for name in
                 ('params', 'features', 'categorical', 'category_maps', 'specs', 'encoded_feature_names',
                  'borders', 'base', 'trees', 'best_iteration')}
        Path(path).write_text(json.dumps({'format': 'scratch_boost_v2', **state}, allow_nan=False), encoding='utf-8')

    @classmethod
    def load(cls, path):
        state = json.loads(Path(path).read_text(encoding='utf-8'))
        version = state.pop('format')
        if version == 'scratch_boost_v1':
            model = _PlainV1Regressor(**state['params'])
        elif version == 'scratch_boost_v2':
            model = cls(**state['params'])
        else:
            raise ValueError('Unsupported model format')
        model.__dict__.update(state)
        return model
