"""Standalone PyTorch implementation of the YOLO26n detection graph."""

import math

import torch
from torch import nn
from torch.nn import functional as F


class Conv(nn.Module):
    def __init__(self, inputs, outputs, kernel=1, stride=1, groups=1, activate=True):
        super().__init__()
        self.conv = nn.Conv2d(inputs, outputs, kernel, stride, kernel // 2, groups=groups, bias=False)
        self.bn = nn.BatchNorm2d(outputs, eps=1e-3, momentum=0.03)
        self.act = nn.SiLU() if activate else nn.Identity()

    def forward(self, x):
        return self.act(self.bn(self.conv(x)))


class Bottleneck(nn.Module):
    def __init__(self, channels, expansion=0.5):
        super().__init__()
        hidden = int(channels * expansion)
        self.cv1 = Conv(channels, hidden, 3)
        self.cv2 = Conv(hidden, channels, 3)

    def forward(self, x):
        return x + self.cv2(self.cv1(x))


class C3k(nn.Module):
    def __init__(self, channels):
        super().__init__()
        hidden = channels // 2
        self.cv1 = Conv(channels, hidden)
        self.cv2 = Conv(channels, hidden)
        self.cv3 = Conv(2 * hidden, channels)
        self.m = nn.Sequential(Bottleneck(hidden, 1), Bottleneck(hidden, 1))

    def forward(self, x):
        return self.cv3(torch.cat((self.m(self.cv1(x)), self.cv2(x)), dim=1))


class Attention(nn.Module):
    def __init__(self, channels):
        super().__init__()
        self.heads = max(channels // 64, 1)
        self.value_dim = channels // self.heads
        self.key_dim = self.value_dim // 2
        self.qkv = Conv(channels, channels + 2 * self.heads * self.key_dim, activate=False)
        self.pe = Conv(channels, channels, 3, groups=channels, activate=False)
        self.proj = Conv(channels, channels, activate=False)

    def forward(self, x):
        batch, channels, height, width = x.shape
        qkv = self.qkv(x).reshape(batch, self.heads, -1, height * width)
        q, k, v = qkv.split((self.key_dim, self.key_dim, self.value_dim), dim=2)
        mixed = F.scaled_dot_product_attention(q.transpose(-1, -2), k.transpose(-1, -2),
                                               v.transpose(-1, -2))
        return self.proj(mixed.transpose(-1, -2).reshape_as(x) + self.pe(v.reshape_as(x)))


class PSA(nn.Module):
    def __init__(self, channels):
        super().__init__()
        self.attn = Attention(channels)
        self.ffn = nn.Sequential(Conv(channels, 2 * channels), Conv(2 * channels, channels, activate=False))

    def forward(self, x):
        x = x + self.attn(x)
        return x + self.ffn(x)


class C2PSA(nn.Module):
    def __init__(self, channels):
        super().__init__()
        self.cv1 = Conv(channels, channels)
        self.cv2 = Conv(channels, channels)
        self.m = nn.Sequential(PSA(channels // 2))

    def forward(self, x):
        bypass, attention = self.cv1(x).chunk(2, dim=1)
        return self.cv2(torch.cat((bypass, self.m(attention)), dim=1))


class C3k2(nn.Module):
    def __init__(self, inputs, outputs, expansion=0.5, block=C3k):
        super().__init__()
        hidden = int(outputs * expansion)
        self.cv1 = Conv(inputs, hidden * 2)
        self.cv2 = Conv(hidden * 3, outputs)
        self.m = nn.ModuleList([block(hidden)])

    def forward(self, x):
        a, b = self.cv1(x).chunk(2, dim=1)
        return self.cv2(torch.cat((a, b, self.m[0](b)), dim=1))


class SPPF(nn.Module):
    def __init__(self, channels):
        super().__init__()
        self.cv1 = Conv(channels, channels // 2, activate=False)
        self.cv2 = Conv(2 * channels, channels)
        self.m = nn.MaxPool2d(5, stride=1, padding=2)

    def forward(self, x):
        levels = [self.cv1(x)]
        for _ in range(3):
            levels.append(self.m(levels[-1]))
        return x + self.cv2(torch.cat(levels, dim=1))


class Concat(nn.Module):
    def forward(self, features):
        return torch.cat(features, dim=1)


class Detect(nn.Module):
    strides = (8, 16, 32)

    def __init__(self, classes):
        super().__init__()
        channels = (64, 128, 256)
        self.cv2 = self.box_towers(channels)
        self.cv3 = self.class_towers(channels, classes)
        self.one2one_cv2 = self.box_towers(channels)
        self.one2one_cv3 = self.class_towers(channels, classes)

    @staticmethod
    def box_towers(channels):
        return nn.ModuleList(nn.Sequential(Conv(c, 16, 3), Conv(16, 16, 3), nn.Conv2d(16, 4, 1))
                             for c in channels)

    @classmethod
    def class_towers(cls, channels, classes):
        towers = nn.ModuleList()
        for c, stride in zip(channels, cls.strides):
            logits = nn.Conv2d(80, classes, 1)
            nn.init.constant_(logits.bias, math.log(5 / classes / (640 / stride) ** 2))
            towers.append(nn.Sequential(
                nn.Sequential(Conv(c, c, 3, groups=c), Conv(c, 80)),
                nn.Sequential(Conv(80, 80, 3, groups=80), Conv(80, 80)),
                logits,
            ))
        return towers

    @staticmethod
    def branch(features, box_towers, class_towers):
        boxes = torch.cat([layer(x).flatten(2) for layer, x in zip(box_towers, features)], dim=2)
        scores = torch.cat([layer(x).flatten(2) for layer, x in zip(class_towers, features)], dim=2)
        return boxes.transpose(1, 2), scores.transpose(1, 2)

    def forward(self, features):
        points, strides = [], []
        for feature, stride in zip(features, self.strides):
            h, w = feature.shape[-2:]
            y, x = torch.meshgrid(torch.arange(h, device=feature.device),
                                  torch.arange(w, device=feature.device), indexing="ij")
            points.append((torch.stack((x, y), dim=-1).reshape(-1, 2) + 0.5) * stride)
            strides.append(torch.full((h * w, 1), stride, device=feature.device))
        one = self.branch([x.detach() for x in features], self.one2one_cv2, self.one2one_cv3)
        many = self.branch(features, self.cv2, self.cv3) if self.training else None
        return one, many, torch.cat(points), torch.cat(strides)


class YOLO26n(nn.Module):
    skip_inputs = {12: (-1, 6), 15: (-1, 4), 18: (-1, 13), 21: (-1, 10)}

    def __init__(self, classes):
        super().__init__()
        self.model = nn.ModuleList([
            Conv(3, 16, 3, 2), Conv(16, 32, 3, 2),
            C3k2(32, 64, 0.25, Bottleneck), Conv(64, 64, 3, 2),
            C3k2(64, 128, 0.25, Bottleneck), Conv(128, 128, 3, 2),
            C3k2(128, 128), Conv(128, 256, 3, 2), C3k2(256, 256),
            SPPF(256), C2PSA(256),
            nn.Upsample(scale_factor=2, mode="nearest"), Concat(), C3k2(384, 128),
            nn.Upsample(scale_factor=2, mode="nearest"), Concat(), C3k2(256, 64),
            Conv(64, 64, 3, 2), Concat(), C3k2(192, 128),
            Conv(128, 128, 3, 2), Concat(),
            C3k2(384, 256, block=lambda c: nn.Sequential(Bottleneck(c), PSA(c))),
            Detect(classes),
        ])

    def forward(self, x):
        outputs = []
        for i, layer in enumerate(self.model[:-1]):
            inputs = [outputs[j] for j in self.skip_inputs[i]] if i in self.skip_inputs else x
            x = layer(inputs)
            outputs.append(x)
        return self.model[-1]([outputs[i] for i in (16, 19, 22)])


def load_pretrained(model, path):
    # The upstream archive stores modules. Restore their attributes into inert shells
    # under PyTorch's restricted unpickler, then transfer only tensor state.
    modules = {
        "block": "SPPF C3k C3k2 PSABlock Bottleneck Attention C2PSA",
        "conv": "Conv DWConv Concat",
        "head": "Detect",
    }
    names = ["ultralytics.nn.tasks.DetectionModel"]
    names += [f"ultralytics.nn.modules.{module}.{name}"
              for module, classes in modules.items() for name in classes.split()]
    standard = [nn.Sequential, nn.ModuleList, nn.Conv2d, nn.MaxPool2d, nn.Upsample,
                nn.SiLU, nn.BatchNorm2d, nn.Identity]
    shells = [(type(name.rsplit(".", 1)[-1], (nn.Module,), {}), name) for name in names]
    with torch.serialization.safe_globals(standard + shells):
        archive = torch.load(path, weights_only=True, map_location="cpu")
    source = (archive.get("ema") or archive["model"]).state_dict()
    replaced = {
        f"model.23.{branch}.{level}.2.{field}"
        for branch in ("cv3", "one2one_cv3") for level in range(3) for field in ("weight", "bias")
    }
    if source.keys() != model.state_dict().keys():
        raise ValueError("Checkpoint tensor keys do not match the supported YOLO26n detection graph.")
    result = model.load_state_dict({k: v for k, v in source.items() if k not in replaced}, strict=False)
    if set(result.missing_keys) != replaced:
        raise ValueError(f"Unexpected missing pretrained tensors: {result.missing_keys}")
    return len(source) - len(replaced)


def decode(distances, points, strides):
    left_top, right_bottom = (distances.float() * strides).chunk(2, dim=-1)
    return torch.cat((points - left_top, points + right_bottom), dim=-1)
