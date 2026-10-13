"""Precision, recall, and COCO-style one-class average precision metrics."""

import numpy as np
import torch

from postprocessing.bbox_utils import xywh_to_xyxy
from postprocessing.nms import box_iou


def _average_precision(recall: np.ndarray, precision: np.ndarray) -> float:
    """Compute 101-point interpolated AP."""
    if recall.size == 0:
        return 0.0
    mrec = np.concatenate(([0.0], recall, [1.0]))
    mpre = np.concatenate(([1.0], precision, [0.0]))
    mpre = np.flip(np.maximum.accumulate(np.flip(mpre)))
    points = np.linspace(0, 1, 101)
    interpolated = np.interp(points, mrec, mpre)
    # Manual trapezoid integration works with both older and newer NumPy releases.
    return float(np.sum((points[1:] - points[:-1]) * (interpolated[1:] + interpolated[:-1]) * 0.5))


def detection_metrics(predictions: list[torch.Tensor], targets: list[torch.Tensor],
                      confidence_threshold: float = 0.5,
                      include_threshold_sweep: bool = True,
                      minimum_precision: float = 0.70) -> dict:
    """Calculate box metrics and an image-level phone-presence confusion matrix."""
    if not 0.0 <= minimum_precision <= 1.0:
        raise ValueError("minimum_precision must be between 0 and 1")
    thresholds = np.arange(0.50, 0.951, 0.05)
    total_ground_truth = sum(len(target) for target in targets)
    stats = [[] for _ in thresholds]
    selected_tp = selected_fp = 0
    best_iou_sum = 0.0
    confusion = {"tn": 0, "fp": 0, "fn": 0, "tp": 0}
    confidence_scores = []
    confidence_tp = []

    for prediction, target in zip(predictions, targets):
        pred = prediction.detach().cpu()
        gt = xywh_to_xyxy(target.detach().cpu()) if len(target) else torch.empty((0, 4))
        scores = pred[:, 4] if len(pred) else torch.empty(0)
        scores_np = scores.numpy()
        selected = scores_np >= confidence_threshold
        selected_tensor = torch.from_numpy(selected)
        actual_phone = len(gt) > 0
        predicted_phone = bool(selected.any())
        if actual_phone and predicted_phone:
            confusion["tp"] += 1
        elif actual_phone:
            confusion["fn"] += 1
        elif predicted_phone:
            confusion["fp"] += 1
        else:
            confusion["tn"] += 1

        # Diagnostic IoU: assign selected boxes to GT boxes by descending IoU.
        # Unmatched ground-truth boxes remain zero in the final per-GT average.
        if len(gt) and len(pred) and bool(selected.any()):
            selected_boxes = pred[selected_tensor, :4]
            ious_for_diagnostic = torch.stack([box_iou(box, gt) for box in selected_boxes])
            flat_order = ious_for_diagnostic.flatten().argsort(descending=True)
            used_predictions, used_ground_truth = set(), set()
            for flat_index in flat_order.tolist():
                prediction_index = flat_index // len(gt)
                ground_truth_index = flat_index % len(gt)
                if prediction_index in used_predictions or ground_truth_index in used_ground_truth:
                    continue
                best_iou_sum += float(ious_for_diagnostic[prediction_index, ground_truth_index])
                used_predictions.add(prediction_index)
                used_ground_truth.add(ground_truth_index)
                if len(used_ground_truth) == len(gt):
                    break

        # Match detections once at IoU 0.50 for confidence-threshold tuning.
        tp_at_50 = np.zeros(len(pred), dtype=np.float32)
        if len(pred) and len(gt):
            ious_at_50 = torch.stack([box_iou(row[:4], gt) for row in pred])
            matched_at_50 = set()
            for prediction_index in scores.argsort(descending=True).tolist():
                available = [index for index in range(len(gt)) if index not in matched_at_50]
                if not available:
                    break
                available_ious = ious_at_50[prediction_index, available]
                best_iou, available_index = available_ious.max(dim=0)
                gt_index = available[int(available_index)]
                if float(best_iou) >= 0.50:
                    tp_at_50[prediction_index] = 1.0
                    matched_at_50.add(int(gt_index))
        confidence_scores.extend(scores_np.tolist())
        confidence_tp.extend(tp_at_50.tolist())

        for threshold_index, iou_threshold in enumerate(thresholds):
            matched = set()
            tp = np.zeros(len(pred), dtype=np.float32)
            if len(pred) and len(gt):
                ious = torch.stack([box_iou(row[:4], gt) for row in pred])
                for prediction_index in scores.argsort(descending=True).tolist():
                    available = [index for index in range(len(gt)) if index not in matched]
                    if not available:
                        break
                    available_ious = ious[prediction_index, available]
                    best_iou, available_index = available_ious.max(dim=0)
                    gt_index = available[int(available_index)]
                    if float(best_iou) >= iou_threshold and int(gt_index) not in matched:
                        tp[prediction_index] = 1.0
                        matched.add(int(gt_index))
            fp = 1.0 - tp
            stats[threshold_index].extend(zip(scores_np.tolist(), tp.tolist(), fp.tolist()))
            if threshold_index == 0:
                selected_tp += int(tp[selected].sum())
                selected_fp += int(selected.sum()) - int(tp[selected].sum())

    precision = selected_tp / max(selected_tp + selected_fp, 1)
    recall = selected_tp / max(total_ground_truth, 1)
    f1 = 2 * precision * recall / max(precision + recall, 1e-12)
    confidence_scores = np.asarray(confidence_scores, dtype=np.float32)
    confidence_tp = np.asarray(confidence_tp, dtype=np.float32)
    threshold_sweep = []
    sweep_values = np.round(np.arange(0.10, 0.951, 0.05), 2) if include_threshold_sweep else []

    def metrics_at_threshold(threshold: float) -> dict:
        keep = confidence_scores >= threshold
        true_positives = int(confidence_tp[keep].sum())
        prediction_count = int(keep.sum())
        threshold_precision = true_positives / max(prediction_count, 1)
        threshold_recall = true_positives / max(total_ground_truth, 1)
        threshold_f1 = 2 * threshold_precision * threshold_recall / max(
            threshold_precision + threshold_recall, 1e-12
        )
        return {
            "threshold": float(threshold),
            "precision": float(threshold_precision),
            "recall": float(threshold_recall),
            "f1": float(threshold_f1),
            "predictions": prediction_count,
        }

    for threshold in sweep_values:
        threshold_sweep.append(metrics_at_threshold(float(threshold)))
    best_threshold = max(
        threshold_sweep,
        key=lambda row: (row["f1"], row["precision"], row["threshold"]),
    ) if threshold_sweep else None
    eligible_thresholds = [
        row for row in threshold_sweep
        if row["predictions"] > 0 and row["precision"] >= minimum_precision
    ]
    if eligible_thresholds:
        selected_threshold = max(
            eligible_thresholds,
            key=lambda row: (row["recall"], row["precision"], row["threshold"]),
        ).copy()
        selected_threshold["meets_minimum_precision"] = True
        selected_threshold["minimum_precision"] = float(minimum_precision)
        selected_threshold["used_configured_fallback"] = False
    elif threshold_sweep:
        selected_threshold = metrics_at_threshold(confidence_threshold)
        selected_threshold["meets_minimum_precision"] = False
        selected_threshold["minimum_precision"] = float(minimum_precision)
        selected_threshold["used_configured_fallback"] = True
    else:
        selected_threshold = None
    aps = []
    for rows in stats:
        if not rows or total_ground_truth == 0:
            aps.append(0.0)
            continue
        rows.sort(key=lambda row: row[0], reverse=True)
        tp = np.cumsum([row[1] for row in rows])
        fp = np.cumsum([row[2] for row in rows])
        aps.append(_average_precision(tp / max(total_ground_truth, 1), tp / np.maximum(tp + fp, 1e-9)))
    return {
        "precision": float(precision),
        "recall": float(recall),
        "f1": float(f1),
        "mean_iou": float(best_iou_sum / total_ground_truth) if total_ground_truth else 0.0,
        "map50": aps[0],
        "map50_95": float(np.mean(aps)),
        "confusion_matrix": confusion,
        "confidence_threshold": float(confidence_threshold),
        "threshold_sweep": threshold_sweep,
        "best_f1_threshold": best_threshold,
        "threshold_selection": selected_threshold,
    }


def format_metrics_report(metrics: dict, split: str = "validation") -> str:
    """Format scores and the phone-presence confusion matrix as a readable report."""
    matrix = metrics["confusion_matrix"]
    lines = [
        f"{split.title()} performance",
        "  Box detection metrics",
        f"    Precision:       {metrics['precision']:.4f}",
        f"    Recall:          {metrics['recall']:.4f}",
        f"    F1 score:        {metrics['f1']:.4f}",
        f"    Mean IoU:        {metrics['mean_iou']:.4f}  (per GT box; misses = 0; conf >= {metrics['confidence_threshold']:.2f})",
        f"    mAP@50:          {metrics['map50']:.4f}  (PR area; IoU >= 0.50 over confidence-ranked boxes)",
        f"    mAP@50-95:       {metrics['map50_95']:.4f}",
    ]
    best_threshold = metrics.get("best_f1_threshold")
    if best_threshold and best_threshold["f1"] > 0:
        lines.append(
            f"    Best F1 threshold: {best_threshold['threshold']:.2f} "
            f"(P={best_threshold['precision']:.4f}, R={best_threshold['recall']:.4f}, "
            f"F1={best_threshold['f1']:.4f})"
        )
    elif best_threshold:
        lines.append("    Best F1 threshold: unavailable (all tested F1 scores are zero)")
    if "loss_components" in metrics:
        components = metrics["loss_components"]
        lines.append(f"    Classification loss: {components['classification']:.4f} (unweighted)")
        lines.append(f"    Box loss:            {components['box']:.4f} (unweighted)")
    if "loss" in metrics:
        lines.append(f"    Loss:            {metrics['loss']:.4f}")
    if "inference_time_ms" in metrics:
        lines.append(f"    Inference time:  {metrics['inference_time_ms']:.2f} ms/image")
    lines.extend([
        "",
        "  Phone presence confusion matrix (rows = actual, columns = predicted)",
        "                         Predicted no phone   Predicted phone",
        f"    Actual no phone      {matrix['tn']:>10}   {matrix['fp']:>14}",
        f"    Actual phone         {matrix['fn']:>10}   {matrix['tp']:>14}",
    ])
    return "\n".join(lines)
