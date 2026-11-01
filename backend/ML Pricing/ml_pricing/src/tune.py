"""Optional validation-only Optuna tuning for the random row split."""
import argparse
from pathlib import Path
import json, time


def tune(data_path, configuration="without_model", trials=30):
    import optuna
    from catboost import CatBoostRegressor, Pool
    from .data_loader import load_data
    from .preprocessing import make_xy
    from .splits import random_row_split
    from .config import ROOT, CATEGORICAL
    df,_=load_data(data_path); X,y=make_xy(df,configuration); s=random_row_split(df)
    tr,va=s["train"],s["validation"]
    train=Pool(X.iloc[tr],y.iloc[tr],cat_features=CATEGORICAL[configuration]); val=Pool(X.iloc[va],y.iloc[va],cat_features=CATEGORICAL[configuration])
    def objective(t):
        p={"iterations":t.suggest_int("iterations",500,2500),"depth":t.suggest_int("depth",4,10),"learning_rate":t.suggest_float("learning_rate",.01,.15,log=True),"l2_leaf_reg":t.suggest_float("l2_leaf_reg",1,10),"random_strength":t.suggest_float("random_strength",0,2),"loss_function":"RMSE","eval_metric":"RMSE","random_seed":42,"verbose":False,"thread_count":-1}
        m=CatBoostRegressor(**p); start=time.perf_counter(); m.fit(train,eval_set=val,early_stopping_rounds=100,verbose=False); t.set_user_attr("training_seconds",time.perf_counter()-start)
        return m.best_score_["validation"]["RMSE"]
    study=optuna.create_study(direction="minimize"); study.optimize(objective,n_trials=trials)
    result={"configuration":configuration,"best_validation_rmse":study.best_value,"best_parameters":study.best_params,"training_seconds":study.best_trial.user_attrs.get("training_seconds"),"trials":trials}
    p=ROOT/"reports"/f"optuna_{configuration}.json"; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(json.dumps(result,indent=2),encoding="utf-8")
    return result


if __name__=="__main__":
    p=argparse.ArgumentParser(); p.add_argument("--data",required=True); p.add_argument("--configuration",choices=["with_model","without_model"],default="without_model"); p.add_argument("--trials",type=int,default=30); a=p.parse_args(); print(json.dumps(tune(a.data,a.configuration,a.trials),indent=2))
