"""Confidence-threshold filtering."""

import torch


def confidence_filter(detections: torch.Tensor, threshold: float = 0.5) -> torch.Tensor:
    """Keep rows [x1,y1,x2,y2,score,class_id] at or above threshold."""
    if detections.numel() == 0:
        return detections.reshape(0, 6)
    return detections[detections[:, 4] >= threshold]
