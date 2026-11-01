import unittest
import importlib.util
import tempfile
from pathlib import Path
import pandas as pd
from ml_pricing.src.config import REQUIRED
from ml_pricing.src.data_loader import validate_data
from ml_pricing.src.preprocessing import make_xy, feature_names
from ml_pricing.src.predict import validate_request


def sample():
    return pd.DataFrame([
        [2,"Apple","iPhone 13",4,128,90,1.0,5.0,1,3899.0,2000.0,2000/3899],
        [4,"Samsung","Galaxy S22",8,256,75,0,2.0,0,2999.0,1200.0,1200/2999],
    ], columns=REQUIRED)


def valid_request():
    return {"deviceAge":3,"brand":"Apple","model":"iPhone 13","ramCapacity":4,"storage":128,
            "internalPerfromanceOverallMark":90,"screenDmgScore":3.5,"totalDmgScore":12,"hasScreenDamage":1,"msrp":3899.0}


class PipelineTests(unittest.TestCase):
    def test_data_validation_accepts_valid_rows(self):
        self.assertEqual(validate_data(sample())["invalid_records"],0)

    def test_real_dataset_loads(self):
        from ml_pricing.src.data_loader import load_data
        df, report=load_data()
        self.assertEqual(len(df),500000)
        self.assertEqual(report["records"],500000)

    def test_missing_required_column_rejected(self):
        with self.assertRaisesRegex(ValueError,"missing required"):
            validate_data(sample().drop(columns="model"))

    def test_features_exclude_targets(self):
        for configuration,expected in (("with_model",10),("without_model",9)):
            X,y=make_xy(sample(),configuration)
            self.assertEqual(X.shape[1],expected)
            self.assertNotIn("actualSoldPrice",X.columns)
            self.assertNotIn("retentationRatio",X.columns)
            self.assertEqual(len(y),len(sample()))

    def test_feature_lists_match_schema(self):
        self.assertIn("model",feature_names("with_model"))
        self.assertNotIn("model",feature_names("without_model"))

    def test_bad_requests_rejected(self):
        for key,value in (("msrp",-1),("deviceAge",11),("internalPerfromanceOverallMark",101),("screenDmgScore",-1),("hasScreenDamage",2)):
            with self.subTest(key=key):
                d=valid_request(); d[key]=value
                with self.assertRaises(ValueError): validate_request(d)

    def test_unseen_brand_and_model_are_safe(self):
        d=valid_request(); d["brand"]="new brand"; d["model"]="new model"
        validate_request(d)

    @unittest.skipUnless(importlib.util.find_spec("catboost"), "CatBoost is unavailable")
    def test_small_training_save_load_seen_unseen_and_rounding(self):
        from catboost import CatBoostRegressor
        from ml_pricing.src.predict import PricePredictor
        from ml_pricing.src.preprocessing import make_xy
        df=pd.concat([sample()]*8,ignore_index=True)
        X,y=make_xy(df,"with_model")
        model=CatBoostRegressor(iterations=10,depth=3,verbose=False,random_seed=42,thread_count=1)
        model.fit(X,y,cat_features=["brand","model"])
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"test.cbm"; model.save_model(path)
            loaded=CatBoostRegressor(); loaded.load_model(path)
            self.assertAlmostEqual(float(model.predict(X.iloc[[0]])[0]),float(loaded.predict(X.iloc[[0]])[0]),places=7)
            predictor=PricePredictor("with_model",path)
            for unseen in (False,True):
                request=valid_request()
                if unseen: request["model"]="unseen model"
                response=predictor.predict(request)
                self.assertGreaterEqual(response["predictedRetentionRatio"],0)
                self.assertLess(response["predictedRetentionRatio"],1)
                self.assertLess(response["estimatedSellingPrice"],request["msrp"])
                self.assertEqual(response["estimatedSellingPrice"],round(request["msrp"]*response["predictedRetentionRatio"],2))


if __name__=="__main__": unittest.main()
