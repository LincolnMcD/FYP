"""C2f feature aggregation block."""

import torch
import torch.nn as nn

from .bottleneck import Bottleneck
from .conv import Conv


class C2f(nn.Module):
    """Split, repeatedly transform, then concatenate intermediate features."""

    def __init__(self, in_channels: int, out_channels: int, repeats: int = 1, expansion: float = 0.5):
        super().__init__()
        hidden = max(1, int(out_channels * expansion))
        self.hidden = hidden
        self.cv1 = Conv(in_channels, 2 * hidden, 1)
        self.blocks = nn.ModuleList(Bottleneck(hidden, hidden, shortcut=True) for _ in range(repeats))
        self.cv2 = Conv((2 + repeats) * hidden, out_channels, 1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        first, second = self.cv1(x).chunk(2, dim=1)
        outputs = [first, second]
        for block in self.blocks:
            outputs.append(block(outputs[-1]))
        return self.cv2(torch.cat(outputs, dim=1))
