"""Display the latest epoch metrics from a training run, optionally following updates."""

import argparse
import json
from pathlib import Path
import time


def format_metrics(metrics, heading):
    def percent(value):
        return "n/a" if value is None else f"{value:.2%}"

    counts = metrics["phone_confusion"]
    accuracy = (counts["tp"] + counts["tn"]) / max(1, sum(counts.values()))
    lines = [heading]
    if "train_loss" in metrics:
        lines.append(f"  Training loss    {metrics['train_loss']:.4f}")
    lines.append(f"  Part mAP@0.50    {percent(metrics['part_map50'])}")
    if "part_map50_95" in metrics:
        lines.append(f"  Part mAP@0.50:0.95  {percent(metrics['part_map50_95'])}")
    if metrics.get("confidence_tuned"):
        lines.append("  Threshold selection  Maximum validation phone F1")
    lines.extend([
        f"  Phone @ {metrics['confidence']:.6g}     "
        f"precision {percent(metrics['phone_precision'])} | recall {percent(metrics['phone_recall'])} "
        f"| F1 {percent(metrics['phone_f1'])} | accuracy {percent(accuracy)}",
        "  Phone confusion matrix",
        "    Actual      | Predicted phone | Predicted non-phone",
        "    ------------+-----------------+--------------------",
        f"    Phone       | {counts['tp']:>15,} | {counts['fn']:>19,}",
        f"    Non-phone   | {counts['fp']:>15,} | {counts['tn']:>19,}",
        "",
    ])
    ap_50_95 = metrics.get("part_ap50_95")
    heading = f"    {'Part':<16} {'AP@0.50':>8}"
    if ap_50_95 is not None:
        heading += f" {'AP@0.50:0.95':>13}"
    lines.append(heading)
    for name, ap in metrics["part_ap50"].items():
        row = f"    {name.removeprefix('mobile-phone-'):<16} {percent(ap):>8}"
        if ap_50_95 is not None:
            row += f" {percent(ap_50_95[name]):>13}"
        lines.append(row)
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("metrics", type=Path, nargs="?", default=Path("runs/phone26n/metrics.jsonl"))
    parser.add_argument("--follow", action="store_true")
    args = parser.parse_args()
    with args.metrics.open(encoding="utf-8") as handle:
        latest = None
        while True:
            position = handle.tell()
            line = handle.readline()
            if not line.endswith("\n"):
                handle.seek(position)
                break
            latest = json.loads(line)
        if latest is not None:
            print_epoch(latest)
        if args.follow:
            try:
                while True:
                    position = handle.tell()
                    line = handle.readline()
                    if line.endswith("\n"):
                        print_epoch(json.loads(line))
                    else:
                        handle.seek(position)
                        time.sleep(1)
            except KeyboardInterrupt:
                return


def print_epoch(metrics):
    epoch = str(metrics["epoch"])
    if "epochs" in metrics:
        epoch += f"/{metrics['epochs']}"
    print(format_metrics(metrics, f"Epoch {epoch} | Validation") + "\n", flush=True)


if __name__ == "__main__":
    main()
