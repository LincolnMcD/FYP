import pandas as pd
import numpy as np
from .config import MODEL_WITH, MODEL_WITHOUT, CATEGORICAL, TARGET, PRICE_TARGET

DAMAGE_FIELDS = ('screenDmgScore', 'backDmgScore', 'frameDmgScore')
LATEST_FEATURES = [name for name in MODEL_WITH if name not in ('totalDmgScore', 'hasScreenDamage')]
LATEST_FEATURES[6:7] = DAMAGE_FIELDS


def load_latest(path, configuration):
    df = pd.read_csv(path, encoding='utf-8-sig')
    required = LATEST_FEATURES + ['actualSoldPrice', 'retentionRatio']
    missing = set(required) - set(df.columns)
    if missing:
        raise ValueError(f'Missing columns: {sorted(missing)}')
    numeric = [name for name in required if name not in ('brand', 'model')]
    df[numeric] = df[numeric].apply(pd.to_numeric)
    if not np.isfinite(df[numeric].to_numpy()).all():
        raise ValueError('Numeric columns must contain finite values')
    for col in ('brand', 'model'):
        df[col] = df[col].astype('string').str.strip().str.casefold()
        if df[col].isna().any() or df[col].eq('').any():
            raise ValueError(f'{col} cannot be blank')
    if not df.deviceAge.between(0, 10).all() or (df.deviceAge % 1 != 0).any():
        raise ValueError('Device age must be a whole number between 0 and 10')
    for col in (*DAMAGE_FIELDS, 'internalPerfromanceOverallMark'):
        if not df[col].between(0, 100).all():
            raise ValueError(f'{col} must be between 0 and 100')
    for col in ('ramCapacity', 'storage'):
        if (df[col] <= 0).any() or (df[col] % 1 != 0).any():
            raise ValueError(f'{col} must be a positive whole number')
    if (df.msrp <= 0).any() or (df.actualSoldPrice <= 0).any() or (df.actualSoldPrice >= df.msrp).any():
        raise ValueError('Require 0 < actualSoldPrice < msrp')
    if not np.allclose(df.retentionRatio, df.actualSoldPrice / df.msrp, atol=1e-8, rtol=0):
        raise ValueError('retentionRatio must equal actualSoldPrice / msrp')
    features = [name for name in LATEST_FEATURES if name != 'model' or configuration == 'with_model']
    return df, df[features], df.retentionRatio


def feature_names(configuration):
    if configuration == "with_model": return MODEL_WITH.copy()
    if configuration == "without_model": return MODEL_WITHOUT.copy()
    raise ValueError("configuration must be 'with_model' or 'without_model'")


def prepare_features(df, configuration):
    names = feature_names(configuration)
    X = df.loc[:, names].copy()
    for col in CATEGORICAL[configuration]:
        X[col] = X[col].fillna("__UNKNOWN__").astype(str).str.strip().str.casefold()
        X.loc[X[col].eq(""), col] = "__UNKNOWN__"
    return X


def make_xy(df, configuration):
    X = prepare_features(df, configuration)
    # Explicitly exclude both target-derived columns.
    assert TARGET not in X.columns and PRICE_TARGET not in X.columns
    return X, df[TARGET].astype(float)
