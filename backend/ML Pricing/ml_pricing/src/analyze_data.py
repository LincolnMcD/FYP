"""Validate the 12-column dataset and materialize quality/split reports."""
import argparse, json
from pathlib import Path
from .config import ROOT, DATASET, TARGET, CATEGORICAL
from .data_loader import load_data, write_report
from .preprocessing import feature_names
from .splits import random_row_split, model_group_split, split_report


def analyze(path=DATASET):
    df, quality=load_data(path)
    reports=ROOT/"reports"; reports.mkdir(parents=True,exist_ok=True)
    write_report(quality,reports/"data_quality.json")
    for name,splitter in (("random",random_row_split),("group",model_group_split)):
        (reports/f"{name}_split.json").write_text(json.dumps(split_report(df,splitter(df)),indent=2),encoding="utf-8")
    models=ROOT/"models"; models.mkdir(parents=True,exist_ok=True)
    schema={"features":{"with_model":feature_names("with_model"),"without_model":feature_names("without_model")},"categorical":CATEGORICAL,"target":TARGET,"forbidden_features":["actualSoldPrice",TARGET]}
    (models/"feature_schema.json").write_text(json.dumps(schema,indent=2),encoding="utf-8")
    print(json.dumps(quality,indent=2,default=str))
    return quality


if __name__=="__main__":
    p=argparse.ArgumentParser(); p.add_argument("--data",default=str(DATASET)); a=p.parse_args(); analyze(a.data)
