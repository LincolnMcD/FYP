"""Spatial pyramid pooling-fast block."""

import torch
import torch
import torch.nn as nn

from .conv import Conv


class SPPF(nn.Module):
    """Pool features at multiple effective receptive-field sizes."""

    def __init__(self, in_channels: int, out_channels: int, kernel_size: int = 5):
        super().__init__()
        hidden = max(1, in_channels // 2)
        self.cv1 = Conv(in_channels, hidden, 1)
        self.pool = nn.MaxPool2d(kernel_size, stride=1, padding=kernel_size // 2)
        self.cv2 = Conv(hidden * 4, out_channels, 1)

    def forward(self, x):
        x = self.cv1(x)
        y1 = self.pool(x)
        y2 = self.pool(y1)
        y3 = self.pool(y2)
        return self.cv2(torch.cat((x, y1, y2, y3), dim=1))
