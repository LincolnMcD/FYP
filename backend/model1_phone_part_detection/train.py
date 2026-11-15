"""Fine-tune YOLO26n and evaluate phone presence and part localization."""

import argparse
from collections import Counter
import json
from itertools import groupby, islice
from pathlib import Path
import random
import sys

import numpy as np
import torch
from torch.utils.data import DataLoader
from tqdm import tqdm
import yaml

from dataset import PhoneDataset, collate, read_examples, split_examples
from detection import detections, iou, pack_targets, training_loss
from show_metrics import format_metrics, print_epoch
from yolo26 import YOLO26n, load_pretrained


def audit(root, seed):
    names, examples, excluded = read_examples(root)
    splits = split_examples(examples, seed)
    for split, items in splits.items():
        parts = Counter(names[int(row[0])] for item in items for row in item.rows)
        positive = sum(bool(item.rows) for item in items)
        print(f"{split}: {len(items)} images, {positive} phone, {len(items) - positive} non-phone")
        print(dict(sorted(parts.items())))
        if len(parts) != len(names) or positive in {0, len(items)}:
            raise ValueError(f"The {split} split does not contain all classes and both image categories.")
    for label in excluded:
        print(f"Excluded: {label}")
    return names, splits, excluded


@torch.inference_mode()
def evaluate(model, loader, device, names, confidence=None, max_batches=0):
    model.eval()
    image_scores = []
    ranked = [[] for _ in names]
    totals = Counter()
    for step, (images, targets, regions) in enumerate(loader, 1):
        output = model(images.to(device, non_blocking=True).float() / 255)
        for boxes, target in zip(detections(output, regions.to(device)).cpu(), targets):
            image_scores.append((float(boxes[:, 4].max()), len(target) > 0))
            by_class = {int(row[0]): row[1:] for row in target}
            totals.update(by_class.keys())
            for row in boxes:
                if row[4] < 0:
                    continue
                cls = int(row[5])
                overlap = float(iou(row[:4], by_class[cls])) if cls in by_class else 0.0
                ranked[cls].append((float(row[4]), overlap))
        if max_batches and step >= max_batches:
            break
    thresholds = np.arange(50, 100, 5) / 100
    per_class = {}
    per_class_50_95 = {}
    for cls, name in enumerate(names):
        if not totals[cls]:
            per_class[name] = None
            per_class_50_95[name] = None
            continue
        overlaps = np.array([overlap for _, overlap in sorted(ranked[cls], key=lambda x: -x[0])])
        ap = [average_precision(overlaps >= threshold, totals[cls]) for threshold in thresholds]
        per_class[name] = ap[0]
        per_class_50_95[name] = float(np.mean(ap))
    ap_values = [value for value in per_class.values() if value is not None]
    ap_50_95_values = [value for value in per_class_50_95.values() if value is not None]
    tuned = confidence is None
    if tuned:
        confidence = select_confidence(image_scores)
    binary = Counter((actual, score >= confidence) for score, actual in image_scores)
    tp, fp = binary[True, True], binary[False, True]
    fn, tn = binary[True, False], binary[False, False]
    return {
        "part_map50": float(np.mean(ap_values)) if ap_values else 0.0,
        "part_ap50": per_class,
        "part_map50_95": float(np.mean(ap_50_95_values)) if ap_50_95_values else 0.0,
        "part_ap50_95": per_class_50_95,
        "phone_precision": tp / max(1, tp + fp),
        "phone_recall": tp / max(1, tp + fn),
        "phone_f1": 2 * tp / max(1, 2 * tp + fp + fn),
        "phone_confusion": {"tp": tp, "fp": fp, "tn": tn, "fn": fn},
        "confidence": confidence,
        "confidence_tuned": tuned,
    }


def select_confidence(image_scores):
    """Maximize phone F1 over observed validation scores, favoring higher thresholds on ties."""
    positives = sum(actual for _, actual in image_scores)
    ranked = sorted(((score, actual) for score, actual in image_scores if score > 0),
                    key=lambda item: -item[0])
    best_threshold, best_tp, best_denominator = 1.0, 0, 1
    tp = predicted = 0
    for score, group in groupby(ranked, key=lambda item: item[0]):
        for _, actual in group:
            predicted += 1
            tp += actual
        denominator = positives + predicted
        if tp * best_denominator > best_tp * denominator:
            best_threshold, best_tp, best_denominator = score, tp, denominator
    return best_threshold


def average_precision(hits, num_labels):
    tp = np.cumsum(hits)
    recall = np.r_[tp / num_labels, 1.0]
    precision = np.r_[tp / np.arange(1, len(tp) + 1), 0.0]
    envelope = np.maximum.accumulate(precision[::-1])[::-1]
    return float(envelope[np.searchsorted(recall, np.linspace(0, 1, 101))].mean())


def save_checkpoint(path, model, names, size, confidence, epoch):
    temporary = path.with_suffix(".tmp")
    torch.save({"model": model.state_dict(), "names": names, "size": size,
                "confidence": confidence, "epoch": epoch}, temporary)
    temporary.replace(path)


def train(args, names, splits, excluded):
    torch.manual_seed(args.seed)
    random.seed(args.seed)
    device = torch.device("cuda" if args.device == "auto" and torch.cuda.is_available()
                          else "cpu" if args.device == "auto" else args.device)
    if device.type == "cuda" and not torch.cuda.is_available():
        raise SystemExit("CUDA is unavailable in this PyTorch installation. See README.md.")
    if device.type == "cpu":
        torch.set_num_threads(min(8, torch.get_num_threads()))
    print(f"Training device: {device}", flush=True)
    args.output.mkdir(parents=True, exist_ok=True)
    if any((args.output / name).exists() for name in ("last.pt", "best.pt", "metrics.jsonl")):
        raise SystemExit(f"Choose a new --output directory. A run already exists in {args.output}.")
    model = YOLO26n(len(names))
    transferred = load_pretrained(model, args.pretrained)
    print(f"Transferred {transferred} pretrained tensors and initialized six new class projections.",
          flush=True)
    model.to(device)
    manifest = {key: [str(item.path.relative_to(args.root)) for item in items]
                for key, items in splits.items()}
    (args.output / "splits.json").write_text(
        json.dumps({"seed": args.seed, "excluded": excluded, **manifest}, indent=2), encoding="utf-8")
    flip_classes = (names.index("mobile-phone-left-view"), names.index("mobile-phone-right-view"))
    loaders = {
        key: DataLoader(PhoneDataset(items, args.size, augment=key == "train", flip_classes=flip_classes),
                        batch_size=args.batch, shuffle=key == "train", num_workers=args.workers,
                        persistent_workers=args.workers > 0, collate_fn=collate,
                        pin_memory=device.type == "cuda")
        for key, items in splits.items()
    }
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.0005)
    steps = min(len(loaders["train"]), args.max_batches) if args.max_batches else len(loaders["train"])
    schedule = torch.optim.lr_scheduler.OneCycleLR(
        optimizer, max_lr=args.lr, total_steps=steps * args.epochs,
        pct_start=0.15, cycle_momentum=False)
    amp = device.type == "cuda"
    scaler = torch.amp.GradScaler(device.type, enabled=amp)
    best = -1.0
    best_epoch = 0
    interactive = sys.stdout.isatty()
    for epoch in range(1, args.epochs + 1):
        model.train()
        total = torch.zeros((), device=device)
        batches = tqdm(islice(loaders["train"], steps), total=steps, desc=f"Epoch {epoch}/{args.epochs}",
                       unit="batch", file=sys.stdout, disable=not interactive)
        for step, (images, targets, _) in enumerate(batches, 1):
            images = images.to(device, non_blocking=True).float() / 255
            targets = pack_targets(targets, device)
            optimizer.zero_grad(set_to_none=True)
            with torch.autocast(device.type, enabled=amp):
                output = model(images)
            progress = ((epoch - 1) * steps + step - 1) / max(1, steps * args.epochs - 1)
            loss = training_loss(output, targets, progress)
            if not torch.isfinite(loss):
                raise RuntimeError(f"Non-finite loss in epoch {epoch}, batch {step}")
            scaler.scale(loss).backward()
            scaler.unscale_(optimizer)
            torch.nn.utils.clip_grad_norm_(model.parameters(), 10)
            scaler.step(optimizer)
            scaler.update()
            schedule.step()
            total += loss.detach()
            if interactive and (step == 1 or step % 10 == 0 or step == steps):
                batches.set_postfix(loss=f"{loss.item():.3f}", refresh=False)
            if not interactive and (step == 1 or step % 100 == 0 or step == steps):
                print(f"Epoch {epoch}/{args.epochs}, batch {step}/{steps}, loss {loss.item():.3f}",
                      flush=True)
        batches.close()
        metrics = evaluate(model, loaders["val"], device, names, args.confidence,
                           args.max_batches)
        metrics.update(epoch=epoch, epochs=args.epochs, train_loss=float(total / steps))
        print_epoch(metrics)
        with (args.output / "metrics.jsonl").open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(metrics) + "\n")
        confidence = metrics["confidence"]
        save_checkpoint(args.output / "last.pt", model, names, args.size, confidence, epoch)
        if metrics["part_map50"] > best:
            best = metrics["part_map50"]
            best_epoch = epoch
            save_checkpoint(args.output / "best.pt", model, names, args.size, confidence, epoch)
        if args.patience and epoch - best_epoch >= args.patience and epoch < args.epochs:
            print(f"Early stopping at epoch {epoch}. Validation mAP50 has not improved "
                  f"for {args.patience} consecutive epochs. Best epoch {best_epoch}, "
                  f"mAP50 {best:.2%}.", flush=True)
            break
    checkpoint = torch.load(args.output / "best.pt", weights_only=True, map_location=device)
    model.load_state_dict(checkpoint["model"])
    test = evaluate(model, loaders["test"], device, names, checkpoint["confidence"], args.max_batches)
    test.update(epoch=checkpoint["epoch"], smoke_test=bool(args.max_batches))
    (args.output / "test_metrics.json").write_text(json.dumps(test, indent=2), encoding="utf-8")
    print(format_metrics(test, f"Test | Best checkpoint from epoch {checkpoint['epoch']}"), flush=True)


def main():
    config_parser = argparse.ArgumentParser(add_help=False)
    config_parser.add_argument("--config", type=Path, default=Path(__file__).with_name("train.yaml"),
                               help="Training configuration file (default: train.yaml)")
    config_args, _ = config_parser.parse_known_args()
    parser = argparse.ArgumentParser(description=__doc__, parents=[config_parser])
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--pretrained", type=Path, default=Path("weights/yolo26n.pt"))
    parser.add_argument("--output", type=Path, default=Path("runs/phone26n"))
    parser.add_argument("--epochs", type=int, default=200, help="Maximum number of epochs (default: 200)")
    parser.add_argument("--patience", type=int, default=20,
                        help="Stop after this many epochs without better validation mAP50 (0 disables)")
    parser.add_argument("--batch", type=int, default=12)
    parser.add_argument("--size", type=int, default=640)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--seed", type=int, default=26)
    parser.add_argument("--lr", type=float, default=0.001)
    parser.add_argument("--confidence", type=float, help="Use a fixed threshold instead of tuning on validation")
    parser.add_argument("--device", choices=("auto", "cuda", "cpu"), default="auto")
    parser.add_argument("--max-batches", type=int, default=0, help="Limit all phases for smoke testing")
    parser.add_argument("--audit-only", action="store_true")
    try:
        config = yaml.safe_load(config_args.config.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as error:
        parser.error(f"Could not read {config_args.config}: {error}")
    if not isinstance(config, dict):
        parser.error(f"{config_args.config} must contain a mapping of training settings.")
    supported = vars(parser.parse_args([])).keys() - {"config", "audit_only"}
    unknown = config.keys() - supported
    if unknown:
        parser.error(f"Unknown settings in {config_args.config}: {', '.join(map(str, unknown))}")
    if "device" in config and config["device"] not in ("auto", "cuda", "cpu"):
        parser.error("Config device must be auto, cuda or cpu.")
    parser.set_defaults(**config)
    args = parser.parse_args()
    if (min(args.epochs, args.batch) < 1 or args.size < 64 or args.size % 32 or args.workers < 0
            or args.max_batches < 0 or args.patience < 0 or args.lr <= 0
            or (args.confidence is not None and not 0 < args.confidence <= 1)):
        parser.error("Use positive epochs, batch and learning rate, size >=64 divisible by 32, "
                     "nonnegative workers, patience and max-batches, and confidence in (0, 1].")
    names, splits, excluded = audit(args.root, args.seed)
    if not args.audit_only:
        train(args, names, splits, excluded)


if __name__ == "__main__":
    main()
