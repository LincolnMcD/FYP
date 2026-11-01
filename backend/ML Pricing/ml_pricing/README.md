# REBYTE CatBoost phone depreciation pipeline

This standalone Python module uses the workspace's `dataset 12col.csv` (the 500,000-row, 12-column synthetic dataset). It does not use the separate 18-column file. All reported scores are synthetic benchmark results and do not establish real-market accuracy.

## From-scratch educational trainer (no CatBoost library)

The separate `src/scratch.py` builds and trains trees using NumPy/Pandas. It does not call CatBoost, XGBoost, LightGBM, or scikit-learn. Version 2 adds:

- **Trees:** symmetric histogram split search, L2-regularized leaf estimates, minimum occupied leaf sizes, minimum split gain, optional feature subsampling, optional Bayesian-style exponential row weights, and split-gain feature importance.
- **Boosting:** `--boosting ordered` (default) maintains separate supporting models at prefix lengths 1, 2, 4, 8, ... in each permutation. The model trained on a prefix supplies residuals for the following block. Every supporting model fits its leaf values using only its own prefix. A random permutation supplies the structure-search residuals at each iteration; all supporting models update using the shared structure. `--boosting plain` remains available for comparisons.
- **Categorical features:** three reproducible permutations by default, aligned with the prefix models; ordered target means with two smoothing strengths; one-hot encoding for small category sets; training-only frequency features; and collision-safe pairs of categorical columns. Unseen categories fall back to the fixed target prior or zero frequency/one-hot indicators. No validation/test labels enter fitting or encoding.

This remains an **independent CatBoost-style approximation**, not a complete CatBoost clone. Ordered-prefix mode shares tree structures and quantile borders across all training rows, and uses dyadic prefixes rather than a separate exact model for every row. It therefore does not guarantee total target independence of learned structures or reproduce CatBoost's split scoring and ordered-gradient rules. Category pairs are enumerated ahead of training rather than selected dynamically, and the implementation lacks compiled/GPU execution and CatBoost model compatibility. See the [CatBoost paper](https://proceedings.neurips.cc/paper_files/paper/2018/hash/14491b756b3a51daac41c24863285549-Abstract.html).

Install the smaller dependencies and start a quick experiment:

```powershell
python -m pip install -r .\ml_pricing\requirements-scratch.txt
python -m ml_pricing.src.train_scratch --strategy group --configuration with_model --iterations 20 --max-rows 5000
```

Train on the entire CSV by omitting `--max-rows`:

```powershell
python -m ml_pricing.src.train_scratch --strategy group --configuration with_model --iterations 200
```

Only one configuration is trained per command. Default depth is 4 and histogram bins is 32. Options include `--depth`, `--bins`, `--learning-rate`, `--patience`, `--boosting`, `--permutations`, `--one-hot-max-size`, `--max-cat-combination`, `--min-samples-leaf`, `--l2`, `--min-gain`, `--feature-fraction`, and `--bagging-temperature`. Feature fraction defaults to 1 and bagging temperature to 0 (disabled); use, for example, `--feature-fraction 0.8 --bagging-temperature 1` to enable both. Minimum occupied leaf sizes constrain structure search in the selected permutation, not unseen inference data. This NumPy implementation can be much slower than the compiled library on 500,000 rows; start small. Prefix models increase training memory and compute. Splits use a deterministic NumPy implementation and are not identical to the library pipeline's scikit-learn splits, so their scores are not a controlled algorithm comparison.

Each run creates a unique directory under `ml_pricing/scratch_runs/` with `report.html`, `learning_curves.png`, `learning_history.csv`, `feature_importance.csv`, `metrics.json`, and `model.json`. All attempted iterations are logged; only the best validation prefix is saved. Test data is evaluated only at the end. Train curves now use the inference encodings, so they match predictions from the deployment ensemble at that iteration; they are resubstitution scores, not unbiased generalization estimates. Deployment leaf values are fitted on ordered training encodings, never on category statistics containing each row's own target. Validation and inference use training-wide category statistics. The CSV also records the selected permutation, tree depth, and (in ordered mode) a post-update prefix-model RMSE diagnostic; the latter can fluctuate as different permutations are selected and is not the deployment model's training loss. The fixed prior is 0.25, also used as the ordered-mode initial prediction, to avoid leaking later labels through a global target mean. Models save in `scratch_boost_v2` format; the loader also reads earlier `scratch_boost_v1` JSON files.

To compare boosting modes, run both commands with the same data, sampling and split options:

```powershell
python -m ml_pricing.src.train_scratch --boosting plain --iterations 100 --max-rows 5000
python -m ml_pricing.src.train_scratch --boosting ordered --iterations 100 --max-rows 5000
```

Ordered-prefix mode is not guaranteed to improve every dataset. Use validation for choosing settings; reserve test data for a final assessment rather than repeated tuning.

Load and predict with the custom model (this JSON format is separate from `.cbm` and the existing API):

```python
from ml_pricing.src.scratch import ScratchBoostRegressor
from ml_pricing.src.preprocessing import prepare_features
import numpy as np

model = ScratchBoostRegressor.load("ml_pricing/scratch_runs/<run>/model.json")
features = prepare_features(phone_dataframe, "with_model")
ratio = model.predict(features)
price_myr = phone_dataframe.msrp.to_numpy() * np.clip(ratio, 0, 0.9999)
```

## Test a saved custom model with the desktop UI

From the workspace root:

```powershell
python ui.py
```

The Tkinter desktop window loads the latest saved custom run automatically. Use the run selector or **Browse model.json** to load a specific run's best validation snapshot. Enter phone specifications, condition and MSRP, then click **Predict retention & price**. An optional actual price displays the absolute and signed error for that example. No retraining is performed. Model names and brands can be typed, including unseen values. Changing inputs or models clears the old prediction. The UI supports both v1 and v2 custom JSON models, not CatBoost `.cbm` files. Tkinter is included with standard python.org Windows installations; the UI otherwise uses the scratch requirements.

To open a specific saved model:

```powershell
python ui.py --model ".\ml_pricing\scratch_runs\<run>\model.json"
```

## CatBoost library setup

From the workspace root in PowerShell:

```powershell
python -m pip install -r .\ml_pricing\requirements.txt
```

## Commands

Validate the dataset and write data quality, split coverage, and feature schema reports (no CatBoost install needed):

```powershell
python -m ml_pricing.src.analyze_data
```

Train both feature configurations with random-row and model-group splits (baseline 1,500 iterations):

```powershell
python -m ml_pricing.src.train
```

Run one strategy or a smaller smoke training run:

```powershell
python -m ml_pricing.src.train --strategy group
python -m ml_pricing.src.train --strategy group --configuration with_model
python -m ml_pricing.src.train --iterations 20
```

Training prints an organized table every boosting iteration (CatBoost adds trees rather than neural-network epochs). Train and validation RMSE, MAE, and R² measure the retention-ratio target: lower RMSE/MAE and higher R² are better. To reduce console output, use `--log-every 50`; every iteration is still saved in `reports/{strategy}_{configuration}_learning_history.csv`. Matching three-panel learning curves are saved in `reports/figures/{strategy}_{configuration}_learning_curves.png`. The dashed line marks the best validation iteration; early stopping can end training before the requested limit. History includes all attempted iterations, while the saved model retains trees through the best iteration.

Final held-out test price MAE/RMSE (MYR), price R², and median absolute price error are recorded in the metrics JSON files. Test data is not used for per-iteration monitoring or early stopping. Confusion matrices, precision, recall, and F1 require categorical labels and are not applicable to this continuous price regression task. These would require a separately defined classification target, such as agreed price bands.

Training also evaluates the held-out test set. Metrics, split coverage, validation report, comparison CSV, and six PNG plots per trained model are written under `ml_pricing/reports/`; models and metadata are written under `ml_pricing/models/`.

Optional validation-only Optuna tuning (never uses the final test split):

```powershell
python -m ml_pricing.src.tune --data ".\dataset 12col.csv" --configuration without_model --trials 30
```

Run API after training:

```powershell
python -m uvicorn ml_pricing.src.api:app --host 127.0.0.1 --port 8000
```

Send `POST http://127.0.0.1:8000/predict-price` with the JSON feature example from the task. The service loads `without_model` once at startup. `actualSoldPrice` and `retentationRatio` are never inference inputs. For a model-inclusive predictor, instantiate `PricePredictor("with_model")`.

Run the test suite:

```powershell
python -m unittest discover -s .\ml_pricing\tests -v
```

## Feature configurations

`with_model` includes the normalized phone model category. `without_model` excludes it and is suitable when production inputs can contain models absent from training. Both use CatBoost's native categorical handling and predict the misspelled CSV target `retentationRatio`; estimated MYR price is MSRP multiplied by the clipped prediction. Production choice should prioritize the model-group test results and account for age and brand coverage recorded in each split report.

## Artifacts

The default model aliases `models/catboost_with_model.cbm` and `models/catboost_without_model.cbm` refer to random-row models. Strategy-specific artifacts are in `models/random/` and `models/group/`. `feature_schema.json`, `training_metadata.json`, `evaluation_metrics.json`, and `model_comparison.csv` are generated after training.
