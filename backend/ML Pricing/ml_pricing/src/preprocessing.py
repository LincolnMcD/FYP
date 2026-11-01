import pandas as pd
from .config import MODEL_WITH, MODEL_WITHOUT, CATEGORICAL, TARGET, PRICE_TARGET


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
