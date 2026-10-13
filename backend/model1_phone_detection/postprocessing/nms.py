"""Pure-PyTorch IoU non-maximum suppression."""

import torch

from .confidence_filter import confidence_filter


def box_iou(box: torch.Tensor, boxes: torch.Tensor) -> torch.Tensor:
    """IoU for one xyxy box against a tensor of xyxy boxes."""
    intersection_min = torch.maximum(box[:2], boxes[:, :2])
    intersection_max = torch.minimum(box[2:], boxes[:, 2:])
    intersection = (intersection_max - intersection_min).clamp(min=0).prod(dim=1)
    area_a = (box[2:] - box[:2]).clamp(min=0).prod()
    area_b = (boxes[:, 2:] - boxes[:, :2]).clamp(min=0).prod(dim=1)
    return intersection / (area_a + area_b - intersection + 1e-7)


def nms(detections: torch.Tensor, iou_threshold: float = 0.5, max_detections: int = 100,
        class_agnostic: bool = True) -> torch.Tensor:
    """Apply descending-score NMS to [x1,y1,x2,y2,score,class_id] rows."""
    if detections.numel() == 0:
        return detections.reshape(0, 6)
    order = detections[:, 4].argsort(descending=True)
    keep = []
    while order.numel() and len(keep) < max_detections:
        current = order[0]
        keep.append(current)
        if order.numel() == 1:
            break
        remaining = order[1:]
        overlaps = box_iou(detections[current, :4], detections[remaining, :4])
        if not class_agnostic:
            same_class = detections[remaining, 5] == detections[current, 5]
            overlaps = overlaps * same_class
        order = remaining[overlaps <= iou_threshold]
    return detections[torch.stack(keep)] if keep else detections[:0]


def filter_and_nms(detections: torch.Tensor, confidence_threshold: float = 0.5,
                   iou_threshold: float = 0.5, max_detections: int = 100) -> torch.Tensor:
    """Apply confidence filtering followed by IoU NMS."""
    return nms(confidence_filter(detections, confidence_threshold), iou_threshold, max_detections)
