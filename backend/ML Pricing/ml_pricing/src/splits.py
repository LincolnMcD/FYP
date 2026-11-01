import numpy as np
from sklearn.model_selection import train_test_split
from .config import SEED


def random_row_split(df):
    idx = np.arange(len(df))
    trainval, test = train_test_split(idx, test_size=0.15, random_state=SEED)
    train, val = train_test_split(trainval, test_size=(0.15 / 0.85), random_state=SEED)
    return {"train": train, "validation": val, "test": test}


def model_group_split(df):
    # Split distinct model keys first so all rows of a model remain together.
    from sklearn.model_selection import GroupShuffleSplit
    groups = df.model.astype(str).to_numpy()
    unique = np.unique(groups)
    gss1 = GroupShuffleSplit(n_splits=1, test_size=0.15, random_state=SEED)
    trainval_g, test_g = next(gss1.split(unique, groups=unique))
    trainval_models, test_models = set(unique[trainval_g]), set(unique[test_g])
    remaining = np.array(sorted(trainval_models))
    gss2 = GroupShuffleSplit(n_splits=1, test_size=0.15 / 0.85, random_state=SEED)
    train_g, val_g = next(gss2.split(remaining, groups=remaining))
    train_models, val_models = set(remaining[train_g]), set(remaining[val_g])
    assert not (train_models & val_models or train_models & test_models or val_models & test_models)
    return {"train": np.flatnonzero(np.isin(groups, list(train_models))),
            "validation": np.flatnonzero(np.isin(groups, list(val_models))),
            "test": np.flatnonzero(np.isin(groups, list(test_models)))}


def split_report(df, splits):
    report = {}
    all_ages = set(map(int, df.deviceAge.unique()))
    all_brands = set(df.brand.unique())
    train_models = set(df.iloc[splits["train"]].model.unique())
    for part, idx in splits.items():
        d = df.iloc[idx]
        report[part] = {"records": len(d), "models": int(d.model.nunique()), "brands": int(d.brand.nunique()),
                        "ages": sorted(map(int, d.deviceAge.unique())), "brand_list": sorted(d.brand.unique().tolist()),
                        "models_list": sorted(d.model.unique().tolist()),
                        "missing_ages_vs_dataset": sorted(all_ages - set(map(int, d.deviceAge.unique()))),
                        "missing_brands_vs_dataset": sorted(all_brands - set(d.brand.unique())),
                        "models_unseen_in_training": sorted(set(d.model.unique()) - train_models) if part != "train" else []}
    return report
