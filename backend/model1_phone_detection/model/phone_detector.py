"""Compact manually implemented YOLOv8-inspired phone detector."""

import torch
import torch.nn as nn

from .c2f import C2f
from .conv import Conv
from .detection_head import DetectionHead
from .pan_fpn import PANFPN
from .sppf import SPPF


class PhoneDetector(nn.Module):
    """Backbone, PAN-FPN neck, and anchor-free one-class detection head."""

    def __init__(self, num_classes: int = 1, width: float = 0.5,
                 backbone: str = "custom", pretrained: bool = False,
                 freeze_backbone_bn: bool = True):
        super().__init__()
        if backbone not in ("custom", "resnet18"):
            raise ValueError("backbone must be custom or resnet18")
        self.backbone_name = backbone
        self.freeze_backbone_bn = freeze_backbone_bn
        self.backbone_frozen = False
        c = lambda value: max(16, int(value * width))
        channels = (c(256), c(512), c(1024))
        if backbone == "resnet18":
            from torchvision.models import resnet18, ResNet18_Weights
            network = resnet18(weights=ResNet18_Weights.IMAGENET1K_V1 if pretrained else None)
            self.backbone = nn.ModuleDict({
                "stem": nn.Sequential(network.conv1, network.bn1, network.relu, network.maxpool),
                "layer1": network.layer1, "layer2": network.layer2,
                "layer3": network.layer3, "layer4": network.layer4,
            })
            self.adapters = nn.ModuleList(Conv(source, target, 1) for source, target in zip((128, 256, 512), channels))
            # Normalize inside the model so all data/inference/overlay paths
            # retain RGB [0,1] inputs and identical geometry.
            self.register_buffer("input_mean", torch.tensor([.485, .456, .406]).view(1, 3, 1, 1))
            self.register_buffer("input_std", torch.tensor([.229, .224, .225]).view(1, 3, 1, 1))
            self.neck = PANFPN(channels)
            self.head = DetectionHead(channels, num_classes=num_classes)
            self.train(self.training)
            return
        self.stem1 = Conv(3, c(64), 3, 2)
        self.stem2 = Conv(c(64), c(128), 3, 2)
        self.stage2 = C2f(c(128), c(128), repeats=1)
        self.down3 = Conv(c(128), c(256), 3, 2)
        self.stage3 = C2f(c(256), c(256), repeats=2)
        self.down4 = Conv(c(256), c(512), 3, 2)
        self.stage4 = C2f(c(512), c(512), repeats=2)
        self.down5 = Conv(c(512), c(1024), 3, 2)
        self.stage5 = C2f(c(1024), c(1024), repeats=1)
        self.sppf = SPPF(c(1024), c(1024))
        self.neck = PANFPN(channels)
        self.head = DetectionHead(channels, num_classes=num_classes)

    def forward(self, images):
        if self.backbone_name == "resnet18":
            images = (images - self.input_mean) / self.input_std
            x = self.backbone["layer1"](self.backbone["stem"](images))
            p3 = self.backbone["layer2"](x)
            p4 = self.backbone["layer3"](p3)
            p5 = self.backbone["layer4"](p4)
            features = tuple(adapter(feature) for adapter, feature in zip(self.adapters, (p3, p4, p5)))
            return self.head(self.neck(features))
        x = self.stage2(self.stem2(self.stem1(images)))
        p3 = self.stage3(self.down3(x))
        p4 = self.stage4(self.down4(p3))
        p5 = self.sppf(self.stage5(self.down5(p4)))
        return self.head(self.neck((p3, p4, p5)))

    def set_backbone_trainable(self, trainable: bool):
        """Freeze/unfreeze pretrained features without resetting the optimizer."""
        if self.backbone_name == "resnet18":
            self.backbone_frozen = not trainable
            for parameter in self.backbone.parameters():
                parameter.requires_grad_(trainable)
            self.train(self.training)

    def train(self, mode: bool = True):
        super().train(mode)
        if self.backbone_name == "resnet18" and mode:
            if self.backbone_frozen:
                self.backbone.eval()
            elif self.freeze_backbone_bn:
                for module in self.backbone.modules():
                    if isinstance(module, nn.BatchNorm2d):
                        module.eval()
        return self


def build_model(config: dict, initialize_pretrained: bool = False):
    settings = config.get("model", {})
    return PhoneDetector(int(settings.get("num_classes", 1)), float(settings.get("width", .5)),
                         backbone=settings.get("backbone", "custom"),
                         pretrained=initialize_pretrained and bool(settings.get("pretrained", False)),
                         freeze_backbone_bn=bool(settings.get("freeze_backbone_bn", True)))
