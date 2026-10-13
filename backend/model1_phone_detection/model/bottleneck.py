"""YOLO-style residual bottleneck."""

import torch.nn as nn

from .conv import Conv


class Bottleneck(nn.Module):
    """Two-convolution bottleneck with an optional residual connection."""

    def __init__(self, in_channels: int, out_channels: int, shortcut: bool = True, expansion: float = 0.5):
        super().__init__()
        hidden = max(1, int(out_channels * expansion))
        self.cv1 = Conv(in_channels, hidden, 1)
        self.cv2 = Conv(hidden, out_channels, 3)
        self.add = shortcut and in_channels == out_channels

    def forward(self, x):
        y = self.cv2(self.cv1(x))
        return x + y if self.add else y
