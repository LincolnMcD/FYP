"""Optimizer and learning-rate scheduler factory."""

import math

import torch


def build_optimizer(model, config: dict):
    """Create AdamW and the configured epoch-based learning-rate scheduler."""
    parameters = model.parameters()
    if getattr(model, "backbone_name", "custom") == "resnet18":
        backbone_factor = float(config.get("optimizer", {}).get("backbone_lr_factor", .1))
        if backbone_factor <= 0:
            raise ValueError("backbone_lr_factor must be positive")
        parameters = [
            {"params": [parameter for name, parameter in model.named_parameters() if not name.startswith("backbone.")],
             "lr": float(config["learning_rate"]), "name": "neck_head"},
            {"params": model.backbone.parameters(), "lr": float(config["learning_rate"]) * backbone_factor,
             "name": "backbone"},
        ]
    optimizer = torch.optim.AdamW(
        parameters, lr=float(config["learning_rate"]),
        weight_decay=float(config.get("weight_decay", 0.0005)),
    )
    total_epochs = int(config.get("epochs", 100))
    min_lr = float(config.get("optimizer", {}).get("min_learning_rate", 1e-5))
    settings = config.get("optimizer", {})
    warmup_epochs = min(int(settings.get("warmup_epochs", 0)), max(0, total_epochs - 1))
    start_factor = float(settings.get("warmup_start_factor", 0.1))
    base_lr = float(config["learning_rate"])
    if total_epochs < 1 or base_lr <= 0 or not 0 <= min_lr <= base_lr:
        raise ValueError("Require positive epochs/learning rate and 0 <= min_learning_rate <= learning_rate")
    if warmup_epochs < 0 or not 0 < start_factor <= 1:
        raise ValueError("Require nonnegative warmup_epochs and 0 < warmup_start_factor <= 1")
    if warmup_epochs:
        def factor(epoch):
            if epoch < warmup_epochs:
                return start_factor + (1.0 - start_factor) * epoch / warmup_epochs
            progress = min(max((epoch - warmup_epochs) / (total_epochs - warmup_epochs), 0.0), 1.0)
            minimum = min_lr / base_lr
            return minimum + (1.0 - minimum) * (1.0 + math.cos(math.pi * progress)) / 2
        scheduler = torch.optim.lr_scheduler.LambdaLR(optimizer, factor)
        scheduler.schedule_signature = (total_epochs, warmup_epochs, start_factor, base_lr, min_lr)
    else:
        scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=total_epochs, eta_min=min_lr)
    return optimizer, scheduler
