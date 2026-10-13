"""Validation and split evaluation entry point."""

import argparse
import time
from pathlib import Path

import torch
from torch.utils.data import DataLoader
from tqdm.auto import tqdm

from evaluation.metrics import detection_metrics, format_metrics_report
from model.phone_detector import build_model
from postprocessing.bbox_utils import decode_predictions
from training.dataset import build_datasets, detection_collate
from training.loss import configured_detection_loss
from utils import evaluation_config_path, load_config, select_device


@torch.no_grad()
def evaluate(model, loader, device, config: dict, progress_description: str = "Validation",
             include_threshold_sweep: bool = True) -> dict:
    """Run loss and detection metrics on a loader and report average latency."""
    model.eval()
    predictions, targets = [], []
    loss_total = 0.0
    component_totals = {"classification": 0.0, "box": 0.0}
    elapsed = 0.0
    item_count = 0
    image_size = int(config.get("image_size", 640))
    infer_config = config.get("inference", {})
    progress = tqdm(loader, desc=progress_description, unit="batch", dynamic_ncols=True, leave=False)
    for images, boxes, _ in progress:
        images = images.to(device)
        device_boxes = [box.to(device) for box in boxes]
        if device.type == "cuda":
            torch.cuda.synchronize(device)
        start = time.perf_counter()
        outputs = model(images)
        if device.type == "cuda":
            torch.cuda.synchronize(device)
        elapsed += time.perf_counter() - start
        loss, components = configured_detection_loss(outputs, device_boxes, config)
        for key in component_totals:
            component_totals[key] += float(components[key]) * len(images)
        loss_total += float(loss.item()) * len(images)
        decoded = decode_predictions(outputs, image_size, confidence_threshold=0.001,
                                     iou_threshold=float(infer_config.get("iou_threshold", 0.5)),
                                     max_detections=int(config.get("evaluation", {}).get("max_detections", 100)))
        predictions.extend(pred.detach().cpu() for pred in decoded)
        targets.extend(box.detach().cpu() for box in boxes)
        item_count += len(images)
        progress.set_postfix(loss=f"{loss_total / max(item_count, 1):.4f}", images=item_count)

    metrics = detection_metrics(
        predictions, targets, float(infer_config.get("confidence_threshold", 0.5)),
        include_threshold_sweep=include_threshold_sweep,
        minimum_precision=float(infer_config.get("minimum_precision", 0.70)),
    )
    metrics["loss_components"] = {key: value / max(item_count, 1) for key, value in component_totals.items()}
    metrics["loss"] = loss_total / max(item_count, 1)
    metrics["inference_time_ms"] = elapsed * 1000 / max(item_count, 1)
    return metrics


def load_model(checkpoint_path: Path, config: dict, device: torch.device):
    """Load detector weights from a training checkpoint."""
    if not checkpoint_path.is_file():
        raise FileNotFoundError(f"Checkpoint not found: {checkpoint_path}. Train the model first.")
    try:
        checkpoint = torch.load(checkpoint_path, map_location=device, weights_only=False)
    except TypeError:
        checkpoint = torch.load(checkpoint_path, map_location=device)
    if isinstance(checkpoint, dict) and "model" in checkpoint and int(checkpoint.get("format_version", 1)) < 2:
        raise ValueError(
            f"Checkpoint {checkpoint_path} uses the previous box-center encoding and is incompatible "
            "with the updated detector. Train a new checkpoint before evaluating or running inference."
        )
    model_settings = dict(config.get("model", {}))
    if isinstance(checkpoint, dict) and checkpoint.get("model_config"):
        model_settings = checkpoint["model_config"]
    else:
        # Existing checkpoints predate configurable backbones.
        model_settings["backbone"] = "custom"
    model = build_model({"model": model_settings}, initialize_pretrained=False).to(device)
    state = checkpoint.get("model", checkpoint) if isinstance(checkpoint, dict) else checkpoint
    model.load_state_dict(state)
    return model


def evaluate_split(split: str, config_path: str | None = None, checkpoint_path: str | None = None) -> dict:
    """Load best checkpoint and evaluate the configured validation or test split."""
    config_path = evaluation_config_path(config_path, checkpoint_path)
    config = load_config(config_path)
    device = select_device(str(config.get("device", "auto")))
    datasets = build_datasets(config)
    dataset = datasets[1] if split == "val" else datasets[2]
    loader = DataLoader(dataset, batch_size=int(config.get("batch_size", 8)), shuffle=False,
                        num_workers=int(config.get("workers", 0)), collate_fn=detection_collate,
                        pin_memory=device.type == "cuda")
    checkpoint = Path(checkpoint_path) if checkpoint_path else config["save_dir"] / "best.pt"
    model = load_model(checkpoint, config, device)
    result = evaluate(
        model, loader, device, config,
        progress_description="Testing" if split == "test" else "Validation",
        include_threshold_sweep=(split == "val"),
    )
    print(format_metrics_report(result, split=split))
    return result


def main(split: str = "val") -> None:
    parser = argparse.ArgumentParser(description=f"Evaluate Model 1 on the {split} split")
    parser.add_argument("--config", default=None, help="Path to config.yaml")
    parser.add_argument("--checkpoint", default=None, help="Checkpoint path (default: saved_models/best.pt)")
    args = parser.parse_args()
    evaluate_split(split, args.config, args.checkpoint)


if __name__ == "__main__":
    main("val")
