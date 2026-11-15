# Phone presence and part detection with YOLO26n

The pipeline implements the YOLO26n model, dual detection heads, loss, training loop, evaluation and prediction in PyTorch. It imports no Ultralytics code. Fine-tuning initializes the backbone, feature pyramid, box heads and classification towers from the official COCO checkpoint. The final classification projections are newly initialized for the seven classes in `Phone/data.yaml`. The custom training recipe uses task-aligned assignment, BCE, CIoU and L1 box losses, AdamW, and on-the-fly image augmentation.

## Dataset

Keep the existing `Phone/images`, `Phone/labels`, `Non Phone/images`, and `Non Phone/label` directories. Each non-phone image has an empty annotation. The loader reads normalized YOLO box rows and converts YOLO polygon rows to their tight axis-aligned boxes in memory.

The loader excludes and reports phone images with more than two annotated boxes or a repeated class. It creates an approximately 80/10/10 split, stratified by phone presence, with byte-identical images and same-source Roboflow variants grouped together. The YAML supplies the class names and their order. The split manifest records the specific files used.

## Preprocessing and feature fusion

Images are EXIF-oriented, converted to RGB, resized with aspect ratio preserved, letterboxed to a square, and scaled to `[0, 1]`. Training randomly combines rotation up to ±15°, zoom from 0.92× to 1.08×, brightness up to ±15%, and contrast and saturation up to ±12%. Each training image has a 50% chance of a horizontal flip. A flip mirrors the bounding boxes and swaps left-view and right-view labels. The loader skips the rotation and zoom if less than 90% of any transformed box's area would remain inside the image. Validation, test, and prediction use deterministic preprocessing.

The YOLO26n neck upsamples deep features and concatenates them with higher-resolution backbone features. It then downsamples and fuses features in the other direction. Detection uses the resulting three maps at strides 8, 16, and 32.

## Run in PowerShell

The downloaded starting checkpoint belongs at `weights/yolo26n.pt`. On a fresh copy, download it from the [official YOLO26n checkpoint release](https://github.com/ultralytics/assets/releases/download/v8.4.0/yolo26n.pt).

The following commands use an isolated environment with CUDA PyTorch for the RTX 3060. If `.venv-gpu` already works, start at the CUDA verification command.

```powershell
python -m venv .venv-gpu
$python = ".\.venv-gpu\Scripts\python.exe"
& $python -m pip install torch==2.10.0 --index-url https://download.pytorch.org/whl/cu128
& $python -m pip install numpy Pillow PyYAML tqdm
& $python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
& $python train.py --audit-only
& $python -u train.py
```

Edit `train.yaml` to change the fine-tuning settings, including the output folder for a fresh run. The trainer loads this file automatically. Command-line options override file settings when supplied, and `--config` selects another YAML file.

For CPU use `python -m pip install -r requirements.txt` and `python train.py --device cpu`. To verify the pipeline quickly, run a separate smoke test:

```powershell
python train.py --device cpu --epochs 1 --max-batches 4 --size 128 --batch 4 --workers 0 --output runs/check
```

The trainer writes `best.pt` (selected by validation part mAP@0.50), `last.pt`, `metrics.jsonl`, `test_metrics.json`, and `splits.json`. Validation and test metrics include part mAP and per-class AP at IoU 0.50 and averaged across IoU thresholds 0.50 to 0.95 in steps of 0.05. Phone metrics use the configured confidence threshold. Smoke-test metrics cover only a few batches.

Training runs for up to 200 epochs by default. It stops early after 20 consecutive epochs without a higher validation part mAP@0.50. An improvement resets the count, and a tie counts toward patience. Use `--patience` to change the limit or `--patience 0` to disable early stopping. After either stop condition, the trainer evaluates `best.pt` on the test split.

In an interactive terminal, the trainer shows a batch progress bar with elapsed time, estimated time remaining for the epoch's training batches, and recent loss. When output is redirected to a file, it writes periodic batch updates. Each completed epoch prints training loss, validation AP metrics, and phone precision, recall, F1, accuracy, and a confusion matrix with actual labels as rows and predicted labels as columns.

Use `Get-Content runs/phone26n/train.log -Wait` to follow batch updates from the background run, or `python show_metrics.py --follow` to display its completed-epoch metrics as a table. Its original records contain mAP@0.50 only.

```powershell
& $python predict.py "path\to\image.jpg" --weights runs/phone26n/best.pt
```

By default, each epoch chooses the confidence threshold that maximizes phone F1 on the validation split. If thresholds tie, the trainer chooses the highest one. The threshold is saved with the epoch's checkpoint. Test evaluation and prediction use the selected checkpoint's saved threshold. Pass `--confidence` to the trainer for a fixed threshold or to the predictor for a one-off override. Part mAP uses confidence-ranked detections.

Prediction returns JSON with a `phone` boolean and up to two boxes in original-image pixels. The two boxes must have different classes. `phone` is true when at least one valid part detection meets the confidence threshold. A saved fine-tuned checkpoint is sufficient for inference.

For a desktop preview, run `& $python ui.py` and click **Open image**. The app uses the best checkpoint in the output folder from `train.yaml` when available. Use **Choose checkpoint** to open another fine-tuned `.pt` file.

Architecture and checkpoint reference: [Ultralytics YOLO26 model definition](https://github.com/ultralytics/ultralytics/blob/main/ultralytics/cfg/models/26/yolo26.yaml) and [YOLO26 end-to-end detection reference](https://docs.ultralytics.com/guides/end2end-detection/).
