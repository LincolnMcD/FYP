"""Bounding-box conversion, prediction decoding, and letterbox reversal."""

import torch

from .confidence_filter import confidence_filter
from .nms import nms


def xywh_to_xyxy(boxes: torch.Tensor) -> torch.Tensor:
    """Convert center-x,center-y,width,height to corner coordinates."""
    result = boxes.clone()
    result[..., :2] = boxes[..., :2] - boxes[..., 2:] / 2
    result[..., 2:] = boxes[..., :2] + boxes[..., 2:] / 2
    return result


def xyxy_to_xywh(boxes: torch.Tensor) -> torch.Tensor:
    """Convert corner coordinates to center-x,center-y,width,height."""
    result = boxes.clone()
    result[..., :2] = (boxes[..., :2] + boxes[..., 2:]) / 2
    result[..., 2:] = boxes[..., 2:] - boxes[..., :2]
    return result


def decode_predictions(outputs, image_size: int, confidence_threshold: float = 0.001,
                       iou_threshold: float = 0.5, max_detections: int = 100) -> list[torch.Tensor]:
    """Decode raw head outputs into per-image normalized xyxy detections."""
    batch_size = outputs[0][0].shape[0]
    predictions = [[] for _ in range(batch_size)]
    for box_logits, class_logits in outputs:
        _, _, height, width = box_logits.shape
        device = box_logits.device
        yy, xx = torch.meshgrid(torch.arange(height, device=device), torch.arange(width, device=device), indexing="ij")
        # The widened tanh offset lets neighboring assigned cells regress the
        # same ground-truth center; dimensions remain normalized sigmoids.
        center_offset = 0.5 + 1.5 * torch.tanh(box_logits[:, :2])
        center_x = (xx[None] + center_offset[:, 0]) / width
        center_y = (yy[None] + center_offset[:, 1]) / height
        sizes = torch.sigmoid(box_logits[:, 2:])
        bw, bh = sizes[:, 0], sizes[:, 1]
        x1, y1 = center_x - bw / 2, center_y - bh / 2
        x2, y2 = center_x + bw / 2, center_y + bh / 2
        scores, class_ids = torch.sigmoid(class_logits).max(dim=1)
        for batch_index in range(batch_size):
            det = torch.stack((x1[batch_index], y1[batch_index], x2[batch_index], y2[batch_index],
                               scores[batch_index], class_ids[batch_index].float()), dim=-1).reshape(-1, 6)
            det = det[(det[:, 2] > det[:, 0]) & (det[:, 3] > det[:, 1])]
            if len(det) > 1000:
                det = det[det[:, 4].topk(1000).indices]
            predictions[batch_index].append(det)
    results = []
    for levels in predictions:
        detections = torch.cat(levels, dim=0) if levels else torch.empty((0, 6))
        detections = confidence_filter(detections, confidence_threshold)
        results.append(nms(detections, iou_threshold, max_detections))
    return results


def undo_letterbox(boxes: torch.Tensor, image_size: int, original_width: int,
                   original_height: int, scale: float, padding: tuple[int, int]) -> torch.Tensor:
    """Convert normalized square-input xyxy boxes to original image pixel coordinates."""
    result = boxes.clone()
    pad_x, pad_y = padding
    result[:, [0, 2]] = (result[:, [0, 2]] * image_size - pad_x) / scale
    result[:, [1, 3]] = (result[:, [1, 3]] * image_size - pad_y) / scale
    result[:, [0, 2]] = result[:, [0, 2]].clamp(0, original_width)
    result[:, [1, 3]] = result[:, [1, 3]].clamp(0, original_height)
    return result
