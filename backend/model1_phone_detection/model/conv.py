"""Convolution, batch-normalization, and SiLU block."""

import torch.nn as nn


class Conv(nn.Module):
    """Standard Conv2d + BatchNorm + SiLU block."""

    def __init__(self, in_channels: int, out_channels: int, kernel_size: int = 1, stride: int = 1):
        super().__init__()
        padding = kernel_size // 2
        self.block = nn.Sequential(
            nn.Conv2d(in_channels, out_channels, kernel_size, stride, padding, bias=False),
            nn.BatchNorm2d(out_channels),
            nn.SiLU(inplace=True),
        )

    def forward(self, x):
        return self.block(x)
