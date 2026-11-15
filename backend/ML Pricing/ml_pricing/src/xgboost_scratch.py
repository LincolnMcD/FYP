"""Independent XGBoost-style squared-error histogram boosting (NumPy/Pandas).

Implements second-order gain, L1/L2 leaf penalties, gamma, depth-wise asymmetric
trees, missing-value directions and row/column sampling. Not the XGBoost package
or its model format. Categorical inputs use training-fitted one-hot encoding.
"""
import json
from pathlib import Path
import numpy as np
import pandas as pd
from .scratch import regression_metrics


class ScratchXGBoostRegressor:
    def __init__(self, iterations=200, depth=6, learning_rate=.05, bins=32,
                 l2=3., l1=0., gamma=0., min_child_weight=5., min_samples_leaf=5,
                 subsample=1., colsample_bytree=1., patience=50, seed=42,
                 early_stopping_metric='retention_rmse'):
        if iterations < 1 or not 1 <= depth <= 12 or not 2 <= bins <= 255 or patience < 1 or min_samples_leaf < 1:
            raise ValueError('Require positive iterations/patience/leaf size, depth 1..12, bins 2..255')
        if not np.isfinite([learning_rate, l2, l1, gamma, min_child_weight, subsample, colsample_bytree]).all():
            raise ValueError('Parameters must be finite')
        if not 0 < learning_rate <= 1 or min(l2, l1, gamma, min_child_weight) < 0:
            raise ValueError('Invalid learning rate or regularization')
        if not 0 < subsample <= 1 or not 0 < colsample_bytree <= 1:
            raise ValueError('Sampling fractions must be in (0,1]')
        if early_stopping_metric not in ('retention_rmse', 'price_mae', 'price_rmse'):
            raise ValueError('Unknown early-stopping metric')
        self.params = dict(iterations=iterations, depth=depth, learning_rate=learning_rate, bins=bins,
                           l2=l2, l1=l1, gamma=gamma, min_child_weight=min_child_weight,
                           min_samples_leaf=min_samples_leaf, subsample=subsample,
                           colsample_bytree=colsample_bytree, patience=patience, seed=seed,
                           early_stopping_metric=early_stopping_metric)

    @staticmethod
    def _keys(series):
        return series.fillna('__UNKNOWN__').astype(str).str.strip().str.casefold()

    def _encode_fit(self, X, categorical):
        self.features, self.categorical = list(X.columns), list(categorical)
        if not self.features or len(set(self.features)) != len(self.features) or not set(categorical).issubset(self.features):
            raise ValueError('Invalid feature columns')
        self.category_values, self.specs, self.borders = {}, [], []
        for col in self.features:
            if col in categorical:
                values = sorted(self._keys(X[col]).unique().tolist())
                if len(values) > 512:
                    raise ValueError(f'{col}: more than 512 categories; this dense one-hot implementation is for moderate cardinality')
                self.category_values[col] = values
                for value in values:
                    self.specs.append({'kind': 'onehot', 'column': col, 'value': value, 'name': f'{col}={value}'})
                    self.borders.append([.5])
            else:
                values = X[col].to_numpy(dtype=float)
                if np.isinf(values).any():
                    raise ValueError('Numeric inputs cannot contain infinity')
                finite = values[np.isfinite(values)]
                edges = np.unique(np.quantile(finite, np.linspace(0, 1, self.params['bins']+1)[1:-1])).tolist() if len(finite) else []
                self.specs.append({'kind': 'numeric', 'column': col, 'name': col})
                self.borders.append(edges)
        return self._transform(X)

    def _transform(self, X):
        X = X.loc[:, self.features]
        columns, cache = [], {}
        for spec, edges in zip(self.specs, self.borders):
            col = spec['column']
            if spec['kind'] == 'onehot':
                if col not in cache:
                    cache[col] = self._keys(X[col])
                values = (cache[col] == spec['value']).to_numpy(dtype=float)
            else:
                values = X[col].to_numpy(dtype=float)
            if np.isinf(values).any():
                raise ValueError('Numeric inputs cannot contain infinity')
            # 0 denotes missing; ordinary bins start at 1.
            binned = np.searchsorted(edges, values, side='left') + 1
            binned[np.isnan(values)] = 0
            columns.append(binned.astype(np.uint16))
        return np.column_stack(columns)

    def _soft(self, gradient):
        return np.sign(gradient)*np.maximum(np.abs(gradient)-self.params['l1'], 0.)

    def _score(self, gradient, hessian):
        return self._soft(gradient)**2/np.maximum(hessian+self.params['l2'], 1e-12)

    def _weight(self, gradient, hessian):
        return float(-self._soft(gradient)/max(hessian+self.params['l2'], 1e-12))

    def _build_tree(self, matrix, gradient, hessian, rows, features):
        nodes = []

        def grow(indices, depth):
            g, h = gradient[indices].sum(), hessian[indices].sum()
            index = len(nodes)
            nodes.append({'value': self._weight(g, h), 'cover': float(h)})
            if depth >= self.params['depth'] or len(indices) < 2*self.params['min_samples_leaf']:
                return index
            best_gain, best = 1e-12, None
            parent = self._score(g, h)
            for feature in features:
                width = len(self.borders[feature])+2
                bins = matrix[indices, feature]
                gs = np.bincount(bins, weights=gradient[indices], minlength=width)
                hs = np.bincount(bins, weights=hessian[indices], minlength=width)
                counts = np.bincount(bins, minlength=width)
                # Include the final numeric bin to allow a missing-versus-present split.
                left_g, left_h, left_n = np.cumsum(gs[1:]), np.cumsum(hs[1:]), np.cumsum(counts[1:])
                for missing_left in (False, True):
                    lg = left_g + (gs[0] if missing_left else 0)
                    lh = left_h + (hs[0] if missing_left else 0)
                    ln = left_n + (counts[0] if missing_left else 0)
                    rh, rn = h-lh, len(indices)-ln
                    gains = .5*(self._score(lg, lh)+self._score(g-lg, rh)-parent)-self.params['gamma']
                    invalid = ((ln < self.params['min_samples_leaf']) | (rn < self.params['min_samples_leaf'])
                               | (lh < self.params['min_child_weight']) | (rh < self.params['min_child_weight']))
                    gains[invalid] = -np.inf
                    threshold = int(np.argmax(gains))
                    if gains[threshold] > best_gain:
                        best_gain = float(gains[threshold])
                        best = (int(feature), threshold+1, missing_left)
            if best is None:
                return index
            feature, threshold, missing_left = best
            bins = matrix[indices, feature]
            left = np.where(bins == 0, missing_left, bins <= threshold)
            left_node = grow(indices[left], depth+1)
            right_node = grow(indices[~left], depth+1)
            nodes[index].update(feature=feature, threshold=threshold, missing_left=missing_left,
                                left=left_node, right=right_node, gain=best_gain)
            return index

        grow(rows, 0)
        return {'nodes': nodes}

    @staticmethod
    def _predict_tree(matrix, tree):
        prediction = np.empty(len(matrix))
        pending = [(0, np.arange(len(matrix)))]
        while pending:
            index, rows = pending.pop()
            node = tree['nodes'][index]
            if 'feature' not in node:
                prediction[rows] = node['value']
                continue
            bins = matrix[rows, node['feature']]
            left = np.where(bins == 0, node['missing_left'], bins <= node['threshold'])
            pending.extend([(node['left'], rows[left]), (node['right'], rows[~left])])
        return prediction

    def fit(self, X, y, X_valid, y_valid, categorical=(), callback=None,
            validation_msrp=None, validation_price=None):
        y, y_valid = np.asarray(y, dtype=float), np.asarray(y_valid, dtype=float)
        if y.ndim != 1 or y_valid.ndim != 1 or len(y) != len(X) or len(y_valid) != len(X_valid) or len(y) < 2 or not len(y_valid):
            raise ValueError('Require matching, nonempty train and validation arrays')
        if not np.isfinite(y).all() or not np.isfinite(y_valid).all():
            raise ValueError('Targets must be finite')
        price_available = validation_msrp is not None and validation_price is not None
        if self.params['early_stopping_metric'] != 'retention_rmse' and not price_available:
            raise ValueError('Price early stopping requires validation MSRP and actual prices')
        if price_available:
            validation_msrp, validation_price = np.asarray(validation_msrp, dtype=float), np.asarray(validation_price, dtype=float)
            if validation_msrp.shape != y_valid.shape or validation_price.shape != y_valid.shape or not np.isfinite(validation_msrp).all() or not np.isfinite(validation_price).all() or (validation_msrp <= 0).any():
                raise ValueError('Invalid validation price arrays')
        train = self._encode_fit(X, categorical)
        valid = self._transform(X_valid)
        self.base = float(y.mean())
        tp, vp = np.full(len(y), self.base), np.full(len(y_valid), self.base)
        self.trees, self.history = [], []
        best, stale, self.best_iteration = float('inf'), 0, 0
        rng = np.random.default_rng(self.params['seed'])
        for iteration in range(1, self.params['iterations']+1):
            # For 1/2*(prediction-target)^2: gradient=p-y, Hessian=1.
            gradient, hessian = tp-y, np.ones(len(y))
            rows = np.arange(len(y))
            if self.params['subsample'] < 1:
                rows = rng.choice(rows, max(1, int(len(y)*self.params['subsample'])), replace=False)
            features = np.arange(train.shape[1])
            if self.params['colsample_bytree'] < 1:
                features = np.sort(rng.choice(features, max(1, int(np.ceil(len(features)*self.params['colsample_bytree']))), replace=False))
            tree = self._build_tree(train, gradient, hessian, rows, features)
            self.trees.append(tree)
            tp += self.params['learning_rate']*self._predict_tree(train, tree)
            vp += self.params['learning_rate']*self._predict_tree(valid, tree)
            row = {'iteration': iteration, 'tree_nodes': len(tree['nodes'])}
            for split, truth, pred in [('train', y, tp), ('validation', y_valid, vp)]:
                row.update({f'{split}_{key}': value for key, value in regression_metrics(truth, pred).items()})
            if price_available:
                prices = validation_msrp*np.clip(vp, 0, .9999)
                row.update({f'validation_price_{key}': value for key, value in regression_metrics(validation_price, prices).items()})
            key = 'validation_rmse' if self.params['early_stopping_metric'] == 'retention_rmse' else 'validation_'+self.params['early_stopping_metric']
            if row[key] < best-1e-12:
                best, stale, self.best_iteration = row[key], 0, iteration
            else:
                stale += 1
            self.history.append(row)
            if callback:
                callback(row)
            if stale >= self.params['patience']:
                break
        self.trees = self.trees[:self.best_iteration]
        return self

    def predict(self, X):
        matrix = self._transform(X)
        prediction = np.full(len(X), self.base)
        for tree in self.trees:
            prediction += self.params['learning_rate']*self._predict_tree(matrix, tree)
        return prediction

    def feature_importance(self):
        gains = np.zeros(len(self.specs))
        for tree in self.trees:
            for node in tree['nodes']:
                if 'feature' in node:
                    gains[node['feature']] += node['gain']
        return pd.DataFrame({'feature': [s['name'] for s in self.specs],
                             'split_gain_percent': gains*100/gains.sum() if gains.sum() else gains}).sort_values('split_gain_percent', ascending=False)

    def save(self, path):
        state = {name: getattr(self, name) for name in ('params', 'features', 'categorical', 'category_values', 'specs', 'borders', 'base', 'trees', 'best_iteration')}
        Path(path).write_text(json.dumps({'format': 'scratch_xgboost_v1', **state}, allow_nan=False), encoding='utf-8')

    @classmethod
    def load(cls, path):
        state = json.loads(Path(path).read_text(encoding='utf-8'))
        if state.pop('format') != 'scratch_xgboost_v1':
            raise ValueError('Not a custom XGBoost-style model')
        model = cls(**state['params']); model.__dict__.update(state)
        return model


def load_custom_model(path):
    version = json.loads(Path(path).read_text(encoding='utf-8')).get('format')
    if version == 'scratch_xgboost_v1':
        return ScratchXGBoostRegressor.load(path)
    if version in ('scratch_boost_v1', 'scratch_boost_v2'):
        from .scratch import ScratchBoostRegressor
        return ScratchBoostRegressor.load(path)
    raise ValueError('Choose a custom-trained model.json (XGBoost-style or legacy CatBoost-style)')
