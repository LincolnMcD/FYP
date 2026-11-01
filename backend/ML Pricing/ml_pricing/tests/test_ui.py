import unittest
from pathlib import Path
import numpy as np
import pandas as pd
from ui import ModelTester, discover_models
from ml_pricing.src.preprocessing import prepare_features


class UITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        paths = discover_models()
        if not paths:
            raise unittest.SkipTest('No saved custom model available')
        cls.tester = ModelTester(paths[0])

    def phone(self):
        return dict(brand='Apple', model='iPhone 13', deviceAge='3', msrp='3899',
                    ramCapacity='4', storage='128', internalPerfromanceOverallMark='90',
                    screenDmgScore='0', totalDmgScore='2', hasScreenDamage='0')

    def test_prediction_matches_saved_model_and_price_calculation(self):
        request = self.phone()
        result = self.tester.predict(request, actual_price=1500)
        X = prepare_features(pd.DataFrame([request]), self.tester.configuration)
        raw = float(self.tester.model.predict(X)[0])
        self.assertAlmostEqual(result['retention_ratio'], np.clip(raw, 0, .9999))
        self.assertEqual(result['estimated_price_myr'], round(3899*result['retention_ratio'], 2))
        self.assertEqual(result['absolute_error_myr'], abs(result['estimated_price_myr']-1500))

    def test_invalid_input_is_rejected(self):
        request = self.phone(); request['msrp'] = '-5'
        with self.assertRaises(ValueError):
            self.tester.predict(request)
        with self.assertRaises(ValueError):
            self.tester.predict(self.phone(), actual_price='nan')

    def test_unseen_categories_can_be_tested(self):
        request = self.phone(); request.update(brand='new brand', model='new phone')
        result = self.tester.predict(request)
        self.assertTrue(np.isfinite(result['estimated_price_myr']))


if __name__ == '__main__':
    unittest.main()
