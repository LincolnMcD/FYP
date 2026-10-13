"""Train Model 1 with validation-based checkpointing and early stopping."""

import argparse
import csv
import random
from pathlib import Path

import numpy as np
import torch
import yaml
from torch.utils.data import DataLoader
from tqdm.auto import tqdm

from evaluation.metrics import format_metrics_report
from evaluation.validate import evaluate
from model.phone_detector import build_model
from training.dataset import PhoneDataset, balanced_diagnostic_samples, build_datasets, detection_collate, limit_samples
from training.loss import configured_detection_loss
from training.diagnostics import compare_batchnorm_modes, save_prediction_overlays
from training.scheduler import build_optimizer
from utils import load_config, select_device


def _seed_everything(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def _checkpoint_state(model, optimizer, scheduler, epoch, best_map, stale_epochs, best_epoch,
                      best_confidence_threshold, model_config=None):
    return {
        "format_version": 2,
        "model_config": model_config,
        "model": model.state_dict(),
        "optimizer": optimizer.state_dict(),
        "scheduler": scheduler.state_dict(),
        "epoch": epoch,
        "best_map50_95": best_map,
        "stale_epochs": stale_epochs,
        "best_epoch": best_epoch,
        "best_confidence_threshold": best_confidence_threshold,
    }


def train(config_path: str | None = None, resume: str | None = None,
          max_train_images: int | None = None, max_val_images: int | None = None,
          epochs: int | None = None, batch_size_override: int | None = None,
          image_size: int | None = None, max_phone_images: int | None = None,
          max_non_phone_images: int | None = None,
          overfit_images: int | None = None, classification_loss: str | None = None,
          classification_target: str | None = None, learning_rate: float | None = None) -> None:
    """Run the configured training process; optionally resume from a checkpoint."""
    config = load_config(config_path)
    if learning_rate is not None:
        if learning_rate <= 0:
            raise ValueError("--learning-rate must be positive")
        config["learning_rate"] = learning_rate
    if classification_loss is not None:
        config.setdefault("loss", {})["classification_mode"] = classification_loss
    if classification_target is not None:
        config.setdefault("loss", {})["classification_target"] = classification_target
    if overfit_images is not None:
        if overfit_images < 2:
            raise ValueError("--overfit-images must be at least 2")
        if resume is not None or max_train_images is not None or max_val_images is not None:
            raise ValueError("Use --overfit-images without --resume or train/validation image limits")
        config.setdefault("augmentation", {})["enabled"] = False
        loss_settings = config.get("loss", {})
        variant = f"{loss_settings.get('classification_mode', 'focal')}_{loss_settings.get('classification_target', 'soft')}"
        if loss_settings.get("negative_mining") == "per_image":
            variant += f"_per_image_neg{float(loss_settings.get('negative_weight', 0.25)):g}"
        variant += f"_lr{float(config['learning_rate']):g}_warmup{int(config.get('optimizer', {}).get('warmup_epochs', 0))}"
        config["save_dir"] = config["save_dir"] / "overfit_diagnostic" / variant
        config["diagnostic"] = {"overfit_images": overfit_images, "evaluation_on_training_images": True}
    if epochs is not None:
        config["epochs"] = epochs
    if batch_size_override is not None:
        config["batch_size"] = batch_size_override
    if image_size is not None:
        if image_size <= 0 or image_size % 32 != 0:
            raise ValueError("Image size must be a positive multiple of 32")
        config["image_size"] = image_size
    if max_phone_images is not None:
        config["dataset"]["max_phone_images"] = max_phone_images
    if max_non_phone_images is not None:
        config["dataset"]["max_non_phone_images"] = max_non_phone_images
    _seed_everything(int(config.get("seed", 42)))
    device = select_device(str(config.get("device", "auto")))
    datasets = build_datasets(config)
    train_set, val_set = datasets[:2]
    train_set.samples = limit_samples(train_set.samples, max_train_images, int(config.get("seed", 42)))
    val_set.samples = limit_samples(val_set.samples, max_val_images, int(config.get("seed", 42)) + 1)
    if overfit_images is not None:
        train_set.samples = balanced_diagnostic_samples(train_set.samples, overfit_images, int(config.get("seed", 42)))
        val_set = PhoneDataset(list(train_set.samples), train_set.image_size, training=False)
        print(f"Memorization diagnostic: training and evaluating the same {len(train_set)} images; augmentation disabled.")
    workers = int(config.get("workers", 0))
    batch_size = int(config.get("batch_size", 8))
    train_loader = DataLoader(train_set, batch_size=batch_size, shuffle=True, num_workers=workers,
                              collate_fn=detection_collate, pin_memory=device.type == "cuda")
    val_loader = DataLoader(val_set, batch_size=batch_size, shuffle=False, num_workers=workers,
                            collate_fn=detection_collate, pin_memory=device.type == "cuda")

    model_config = config.get("model", {})
    if model_config.get("pretrained", False) and model_config.get("backbone") == "resnet18" and resume is None:
        torch.hub.set_dir(str(config["_project_root"] / ".cache" / "torch"))
        print("Loading ImageNet-pretrained ResNet-18 backbone (downloads weights on first use)...", flush=True)
    model = build_model(config, initialize_pretrained=resume is None).to(device)
    optimizer, scheduler = build_optimizer(model, config)
    save_dir: Path = config["save_dir"]
    save_dir.mkdir(parents=True, exist_ok=True)
    run_config = {key: value for key, value in config.items() if not key.startswith("_")}
    run_config["save_dir"] = str(save_dir)
    run_config["dataset"]["root"] = str(run_config["dataset"]["root"])
    for key in ("train_path", "val_path", "test_path"):
        if run_config["dataset"].get(key):
            run_config["dataset"][key] = str(run_config["dataset"][key])
    with (save_dir / "run_config.yaml").open("w", encoding="utf-8") as stream:
        yaml.safe_dump(run_config, stream, sort_keys=False)
    best_path, last_path = save_dir / "best.pt", save_dir / "last.pt"
    threshold_csv = save_dir / "validation_thresholds.csv"
    csv_mode = "a" if resume is not None else "w"
    if csv_mode == "w" or not threshold_csv.exists():
        with threshold_csv.open("w", newline="", encoding="utf-8") as stream:
            csv.writer(stream).writerow(
                ("epoch", "confidence_threshold", "precision", "recall", "f1", "predictions")
            )
    start_epoch, best_map, stale_epochs, best_epoch = 0, -1.0, 0, -1
    best_confidence_threshold = float(config.get("inference", {}).get("confidence_threshold", 0.5))

    if resume is not None:
        checkpoint_path = Path(resume) if resume else last_path
        if not checkpoint_path.is_absolute():
            checkpoint_path = (Path.cwd() / checkpoint_path).resolve()
        if not checkpoint_path.is_file():
            raise FileNotFoundError(f"Resume checkpoint not found: {checkpoint_path}")
        try:
            checkpoint = torch.load(checkpoint_path, map_location=device, weights_only=False)
        except TypeError:
            checkpoint = torch.load(checkpoint_path, map_location=device)
        if int(checkpoint.get("format_version", 1)) < 2:
            raise ValueError(
                "This checkpoint uses the previous box-center encoding and cannot be resumed safely. "
                "Start a fresh training run with the updated loss."
            )
        saved_model_config = checkpoint.get("model_config") or {"backbone": "custom"}
        if saved_model_config.get("backbone", "custom") != model_config.get("backbone", "custom"):
            raise ValueError("Checkpoint backbone differs from configuration; start fresh or use its saved run config")
        model.load_state_dict(checkpoint["model"])
        if checkpoint["scheduler"].get("schedule_signature") != getattr(scheduler, "schedule_signature", None):
            raise ValueError("Resume scheduler settings differ from this checkpoint. Use its saved run config or start fresh.")
        optimizer.load_state_dict(checkpoint["optimizer"])
        scheduler.load_state_dict(checkpoint["scheduler"])
        start_epoch = int(checkpoint["epoch"]) + 1
        best_map = float(checkpoint.get("best_map50_95", -1.0))
        stale_epochs = int(checkpoint.get("stale_epochs", 0))
        best_epoch = int(checkpoint.get("best_epoch", checkpoint["epoch"]))
        print(f"Resumed from {checkpoint_path} at epoch {start_epoch + 1}")
        print("Confidence threshold will use the configured fallback unless validation meets the precision target.")

    patience = int(config.get("early_stopping_patience", 15))
    clip_norm = float(config.get("optimizer", {}).get("gradient_clip_norm", 10.0))
    if clip_norm <= 0:
        raise ValueError("gradient_clip_norm must be positive")
    optimization_csv = save_dir / "optimization.csv"
    if resume is None or not optimization_csv.exists():
        with optimization_csv.open("w", newline="", encoding="utf-8") as stream:
            csv.writer(stream).writerow(("epoch", "learning_rate", "gradient_norm_mean", "gradient_norm_max", "clipped_updates", "updates", "clipped_percent"))
    epochs = int(config.get("epochs", 100))
    if overfit_images is not None:
        patience = epochs + 1
        with (save_dir / "training_subset.txt").open("w", encoding="utf-8") as stream:
            stream.write("\n".join(str(sample["image"]) for sample in train_set.samples) + "\n")
    for epoch in range(start_epoch, epochs):
        if model.backbone_name == "resnet18":
            trainable = epoch >= int(model_config.get("freeze_backbone_epochs", 5))
            model.set_backbone_trainable(trainable)
            print(f"ResNet-18 backbone: {'fine-tuning' if trainable else 'frozen'}", flush=True)
        model.train()
        train_loss = 0.0
        component_totals = {"classification": 0.0, "box": 0.0}
        image_count = 0
        epoch_lr = optimizer.param_groups[0]["lr"]
        gradient_sum = gradient_max = 0.0
        clipped_updates = update_count = 0
        train_progress = tqdm(
            train_loader, desc=f"Epoch {epoch + 1}/{epochs} - training", unit="batch",
            dynamic_ncols=True, leave=False,
        )
        for images, boxes, _ in train_progress:
            images = images.to(device)
            boxes = [box.to(device) for box in boxes]
            optimizer.zero_grad(set_to_none=True)
            outputs = model(images)
            loss, components = configured_detection_loss(outputs, boxes, config)
            if not torch.isfinite(loss):
                raise FloatingPointError(f"Non-finite training loss at epoch {epoch + 1}")
            loss.backward()
            gradient_norm = float(torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=clip_norm,
                                                                error_if_nonfinite=True))
            gradient_sum += gradient_norm
            gradient_max = max(gradient_max, gradient_norm)
            clipped_updates += int(gradient_norm > clip_norm)
            update_count += 1
            optimizer.step()
            train_loss += float(loss.detach()) * len(images)
            image_count += len(images)
            for key in component_totals:
                component_totals[key] += float(components[key]) * len(images)
            train_progress.set_postfix(loss=f"{float(loss.detach()):.4f}", grad=f"{gradient_norm:.2f}", lr=f"{epoch_lr:.2g}")

        validation = evaluate(
            model, val_loader, device, config,
            progress_description=f"Epoch {epoch + 1}/{epochs} - {'training subset evaluation' if overfit_images is not None else 'validation'}",
        )
        if overfit_images is not None and (epoch == 0 or (epoch + 1) % 10 == 0 or epoch + 1 == epochs):
            bn_result = compare_batchnorm_modes(model, val_loader, device, config)
            print(f"BatchNorm check (same batch): eval loss={bn_result['eval_loss']:.4f}, "
                  f"batch-stat loss={bn_result['batch_stat_loss']:.4f}, "
                  f"mean score difference={bn_result['score_difference']:.4f}")
            save_prediction_overlays(model, val_loader, device, config, save_dir / "overlays" / f"epoch_{epoch + 1:03d}")
        with threshold_csv.open("a", newline="", encoding="utf-8") as stream:
            writer = csv.writer(stream)
            for row in validation["threshold_sweep"]:
                writer.writerow((epoch + 1, row["threshold"], row["precision"], row["recall"],
                                 row["f1"], row["predictions"]))
        scheduler.step()
        mean_train_loss = train_loss / max(image_count, 1)
        clipped_percent = 100 * clipped_updates / max(update_count, 1)
        with optimization_csv.open("a", newline="", encoding="utf-8") as stream:
            csv.writer(stream).writerow((epoch + 1, epoch_lr, gradient_sum / max(update_count, 1),
                                        gradient_max, clipped_updates, update_count, clipped_percent))
        score = validation["map50_95"]
        improved = score > best_map
        if improved:
            best_map = score
            stale_epochs = 0
            best_epoch = epoch
            threshold_selection = validation.get("threshold_selection")
            if threshold_selection and threshold_selection["meets_minimum_precision"]:
                best_confidence_threshold = threshold_selection["threshold"]
            else:
                best_confidence_threshold = float(
                    config.get("inference", {}).get("confidence_threshold", 0.5)
                )
        else:
            stale_epochs += 1

        state = _checkpoint_state(model, optimizer, scheduler, epoch, best_map, stale_epochs,
                                  best_epoch, best_confidence_threshold, dict(model_config))
        torch.save(state, last_path)
        if improved:
            torch.save(state, best_path)
        print(f"\nEpoch {epoch + 1}/{epochs} | training loss: {mean_train_loss:.4f}")
        print(f"Optimization: LR={epoch_lr:.6g} | gradient norm before clipping: "
              f"mean={gradient_sum / max(update_count, 1):.2f}, max={gradient_max:.2f} | "
              f"clipped={clipped_updates}/{update_count} ({clipped_percent:.1f}%)")
        print(f"Training components (unweighted): classification={component_totals['classification'] / max(image_count, 1):.4f}, "
              f"box={component_totals['box'] / max(image_count, 1):.4f}")
        print(format_metrics_report(validation, split="training subset diagnostic" if overfit_images is not None else "validation"))
        if stale_epochs >= patience:
            print(f"Early stopping: validation mAP@50-95 did not improve for {patience} epochs.")
            break

    run_config.setdefault("inference", {})["confidence_threshold"] = best_confidence_threshold
    with (save_dir / "run_config.yaml").open("w", encoding="utf-8") as stream:
        yaml.safe_dump(run_config, stream, sort_keys=False)
    print()
    print(f"Best checkpoint: {best_path}")
    print(f"Best checkpoint epoch: {best_epoch + 1}")
    print(f"Confidence threshold selected from that epoch's validation set: {best_confidence_threshold:.2f}")
    print(f"Last checkpoint: {last_path}")
    print(f"Validation confidence-threshold history: {threshold_csv}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Train the custom YOLOv8-inspired phone detector")
    parser.add_argument("--config", default=None, help="Path to config.yaml")
    parser.add_argument("--learning-rate", type=float, default=None, help="Override base learning rate for comparisons")
    parser.add_argument("--classification-loss", choices=("bce", "focal"), default=None,
                        help="Override classification loss for a controlled comparison")
    parser.add_argument("--classification-target", choices=("binary", "soft"), default=None,
                        help="Binary phone/background targets or previous IoU-based soft targets")
    parser.add_argument("--overfit-images", type=int, default=None,
                        help="Disable augmentation and train/evaluate the same small subset; saves in overfit_diagnostic/")
    parser.add_argument("--resume", nargs="?", const="", default=None,
                        help="Resume from a checkpoint; without a path, uses saved_models/last.pt")
    parser.add_argument("--max-train-images", type=int, default=None,
                        help="Limit training to a deterministic subset (useful for a quick smoke run)")
    parser.add_argument("--max-val-images", type=int, default=None,
                        help="Limit validation images for a quick smoke run")
    parser.add_argument("--epochs", type=int, default=None, help="Override the configured epoch count")
    parser.add_argument("--batch-size", type=int, default=None, help="Override the configured batch size")
    parser.add_argument("--image-size", type=int, default=None, help="Override input size (multiple of 32)")
    parser.add_argument("--max-phone-images", type=int, default=None,
                        help="Cap Phone images before the 70/15/15 split")
    parser.add_argument("--max-non-phone-images", type=int, default=None,
                        help="Cap Non Phone images before the 70/15/15 split")
    args = parser.parse_args()
    train(args.config, args.resume, args.max_train_images, args.max_val_images,
          args.epochs, args.batch_size, args.image_size,
          args.max_phone_images, args.max_non_phone_images, args.overfit_images, args.classification_loss,
          args.classification_target, args.learning_rate)


if __name__ == "__main__":
    main()
