"""Read-only checks and overlays for the small memorization diagnostic."""

from pathlib import Path

import torch
from PIL import Image, ImageDraw

from postprocessing.bbox_utils import decode_predictions, xywh_to_xyxy
from training.loss import configured_detection_loss


@torch.no_grad()
def compare_batchnorm_modes(model, loader, device, config):
    """Compare running vs batch statistics without changing model buffers/modes."""
    images, boxes, _ = next(iter(loader))
    images = images.to(device)
    boxes = [box.to(device) for box in boxes]
    modes = {module: module.training for module in model.modules()}
    buffers = {name: value.clone() for name, value in model.named_buffers()}
    try:
        model.eval()
        eval_outputs = model(images)
        eval_loss, _ = configured_detection_loss(eval_outputs, boxes, config)
        # Only BatchNorm uses training mode; dropout and other layers stay in eval.
        for module in model.modules():
            if isinstance(module, torch.nn.modules.batchnorm._BatchNorm):
                module.train()
        batch_outputs = model(images)
        batch_loss, _ = configured_detection_loss(batch_outputs, boxes, config)
        difference = torch.cat([
            (eval_pair[1].sigmoid() - batch_pair[1].sigmoid()).abs().flatten()
            for eval_pair, batch_pair in zip(eval_outputs, batch_outputs)
        ]).mean()
        return {"eval_loss": float(eval_loss), "batch_stat_loss": float(batch_loss),
                "score_difference": float(difference)}
    finally:
        for name, value in model.named_buffers():
            value.copy_(buffers[name])
        for module, mode in modes.items():
            module.training = mode


@torch.no_grad()
def save_prediction_overlays(model, loader, device, config, output_dir: Path, maximum: int = 8):
    """Draw GT in green and up to ten predictions at confidence >= .10 in red."""
    output_dir.mkdir(parents=True, exist_ok=True)
    modes = {module: module.training for module in model.modules()}
    saved = 0
    settings = config.get("inference", {})
    try:
        model.eval()
        for images, boxes, names in loader:
            predictions = decode_predictions(
                model(images.to(device)), int(config.get("image_size", 640)),
                confidence_threshold=0.10,
                iou_threshold=float(settings.get("iou_threshold", 0.5)), max_detections=10,
            )
            for tensor, target, prediction, name in zip(images, boxes, predictions, names):
                pixels = (tensor.permute(1, 2, 0).cpu().clamp(0, 1).numpy() * 255).astype("uint8")
                image = Image.fromarray(pixels)
                draw = ImageDraw.Draw(image)
                width, height = image.size
                scale = torch.tensor([width, height, width, height])
                for box in xywh_to_xyxy(target.cpu()) * scale:
                    draw.rectangle(box.tolist(), outline="lime", width=2)
                for row in prediction.cpu():
                    box = row[:4] * scale
                    draw.rectangle(box.tolist(), outline="red", width=2)
                    draw.text((float(box[0]), float(box[1])), f"{float(row[4]):.2f}", fill="red")
                draw.text((4, 4), "Green: GT | Red: predictions >= 0.10 (top 10)", fill="white", stroke_width=1, stroke_fill="black")
                image.save(output_dir / f"{saved:02d}_{Path(name).stem}.jpg")
                saved += 1
                if saved >= maximum:
                    return
    finally:
        for module, mode in modes.items():
            module.training = mode
