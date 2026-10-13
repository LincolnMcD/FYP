"""Anchor-free, decoupled multi-scale detection head."""

import torch.nn as nn

from .conv import Conv


class DetectionHead(nn.Module):
    """Separate box and class branches for each PAN-FPN feature level."""

    def __init__(self, channels: tuple[int, int, int] = (128, 256, 512), num_classes: int = 1):
        super().__init__()
        self.box_branches = nn.ModuleList()
        self.class_branches = nn.ModuleList()
        for channel in channels:
            hidden = max(32, channel // 2)
            self.box_branches.append(nn.Sequential(Conv(channel, hidden, 3), Conv(hidden, hidden, 3), nn.Conv2d(hidden, 4, 1)))
            self.class_branches.append(nn.Sequential(Conv(channel, hidden, 3), Conv(hidden, hidden, 3), nn.Conv2d(hidden, num_classes, 1)))

    def forward(self, features):
        return [(box(feature), cls(feature)) for feature, box, cls in zip(features, self.box_branches, self.class_branches)]
