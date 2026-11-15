"""Predict phone presence and up to two distinct phone-part classes."""

import argparse
import json
from pathlib import Path

import torch

from dataset import letterbox
from detection import detections
from yolo26 import YOLO26n


def load_model(weights, device):
    checkpoint = torch.load(weights, weights_only=True, map_location="cpu")
    model = YOLO26n(len(checkpoint["names"]))
    model.load_state_dict(checkpoint["model"])
    return model.to(device).eval(), checkpoint


@torch.inference_mode()
def predict(model, path, size, names, confidence, device):
    tensor, (width, height, resized_w, resized_h, left, top) = letterbox(path, size)
    output = model(tensor[None].to(device).float() / 255)
    parts = []
    region = torch.tensor([[left, top, left + resized_w, top + resized_h]], device=device)
    for x1, y1, x2, y2, score, cls in detections(output, region)[0].cpu().tolist():
        if score < confidence:
            continue
        x1, x2 = (min(width, max(0, (x - left) * width / resized_w)) for x in (x1, x2))
        y1, y2 = (min(height, max(0, (y - top) * height / resized_h)) for y in (y1, y2))
        if x2 > x1 and y2 > y1:
            parts.append({"class": names[int(cls)], "confidence": round(score, 5),
                          "xyxy": [round(x, 2) for x in (x1, y1, x2, y2)]})
    return {"image": str(path), "phone": bool(parts), "parts": parts}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--weights", type=Path, default=Path("runs/phone26n/best.pt"))
    parser.add_argument("--confidence", type=float)
    args = parser.parse_args()
    if args.confidence is not None and not 0 < args.confidence <= 1:
        parser.error("Confidence must be in (0, 1].")
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model, checkpoint = load_model(args.weights, device)
    confidence = checkpoint["confidence"] if args.confidence is None else args.confidence
    print(json.dumps(predict(model, args.image, checkpoint["size"], checkpoint["names"],
                             confidence, device), indent=2))


if __name__ == "__main__":
    main()
