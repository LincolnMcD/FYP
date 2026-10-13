"""Top-down FPN and bottom-up PAN feature fusion."""

import torch
import torch.nn as nn
import torch.nn.functional as F

from .c2f import C2f
from .conv import Conv


class PANFPN(nn.Module):
    """Fuse backbone P3/P4/P5 tensors and return three detection scales."""

    def __init__(self, channels: tuple[int, int, int] = (128, 256, 512)):
        super().__init__()
        c3, c4, c5 = channels
        self.top4 = C2f(c4 + c5, c4, repeats=1)
        self.top3 = C2f(c3 + c4, c3, repeats=1)
        self.down3 = Conv(c3, c3, 3, 2)
        self.pan4 = C2f(c3 + c4 + c4, c4, repeats=1)
        self.down4 = Conv(c4, c4, 3, 2)
        self.pan5 = C2f(c4 + c5, c5, repeats=1)

    def forward(self, features):
        p3, p4, p5 = features
        td4 = self.top4(torch.cat((p4, F.interpolate(p5, size=p4.shape[-2:], mode="nearest")), dim=1))
        td3 = self.top3(torch.cat((p3, F.interpolate(td4, size=p3.shape[-2:], mode="nearest")), dim=1))
        pan4 = self.pan4(torch.cat((self.down3(td3), p4, td4), dim=1))
        pan5 = self.pan5(torch.cat((self.down4(pan4), p5), dim=1))
        return td3, pan4, pan5
