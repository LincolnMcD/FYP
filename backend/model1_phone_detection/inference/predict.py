"""Run phone detection on one image and save an annotated copy."""

import argparse
import json
from pathlib import Path

import cv2
import torch

from evaluation.validate import load_model
from postprocessing.bbox_utils import decode_predictions, undo_letterbox
from postprocessing.confidence_filter import confidence_filter
from postprocessing.nms import nms
from preprocessing.letterbox import letterbox
from preprocessing.orientation import load_oriented_rgb
from utils import evaluation_config_path, load_config, select_device


@torch.no_grad()
def predict_image(image_path: str | Path, checkpoint_path: str | Path | None = None,
                  output_path: str | Path | None = None, config_path: str | Path | None = None,
                  save_annotated: bool = True) -> dict:
    """Predict phone boxes, optionally save an annotated image, and return JSON-friendly detections."""
    config_path = evaluation_config_path(config_path, checkpoint_path)
    config = load_config(config_path)
    device = select_device(str(config.get("device", "auto")))
    image_path = Path(image_path)
    if not image_path.is_file():
        raise FileNotFoundError(f"Input image not found: {image_path}")
    checkpoint_path = Path(checkpoint_path) if checkpoint_path else config["save_dir"] / "best.pt"
    model = load_model(checkpoint_path, config, device)
    model.eval()

    rgb = load_oriented_rgb(image_path)
    original_height, original_width = rgb.shape[:2]
    image_size = int(config.get("image_size", 640))
    resized, scale, padding = letterbox(rgb, image_size)
    tensor = torch.from_numpy(resized.transpose(2, 0, 1).copy()).float().div_(255.0).unsqueeze(0).to(device)
    outputs = model(tensor)
    settings = config.get("inference", {})
    detections = decode_predictions(outputs, image_size, confidence_threshold=0.001,
                                    iou_threshold=float(settings.get("iou_threshold", 0.5)),
                                    max_detections=int(settings.get("max_detections", 100)))[0]
    detections = confidence_filter(detections, float(settings.get("confidence_threshold", 0.5)))
    detections = nms(detections, float(settings.get("iou_threshold", 0.5)),
                     int(settings.get("max_detections", 100)))
    pixel_boxes = undo_letterbox(detections[:, :4], image_size, original_width, original_height, scale, padding)

    results = []
    for detection, box in zip(detections, pixel_boxes):
        x1, y1, x2, y2 = [int(round(float(value))) for value in box]
        results.append({
            "class": "phone",
            "class_id": 0,
            "confidence": float(detection[4]),
            "bounding_box": {"x1": x1, "y1": y1, "x2": x2, "y2": y2},
        })

    output_file_str = None
    if save_annotated:
        annotated = rgb.copy()
        for result in results:
            box = result["bounding_box"]
            cv2.rectangle(annotated, (box["x1"], box["y1"]), (box["x2"], box["y2"]), (0, 255, 0), 2)
            label = f"phone {result['confidence']:.2f}"
            cv2.putText(annotated, label, (box["x1"], max(18, box["y1"] - 6)),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2, cv2.LINE_AA)
        output_path = Path(output_path) if output_path else image_path.with_name(f"{image_path.stem}_prediction.jpg")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        if not cv2.imwrite(str(output_path), cv2.cvtColor(annotated, cv2.COLOR_RGB2BGR)):
            raise OSError(f"Could not save annotated image: {output_path}")
        output_file_str = str(output_path.resolve())

    return {"image": str(image_path.resolve()), "detections": results, "output_image": output_file_str}


def main() -> None:
    parser = argparse.ArgumentParser(description="Detect phone bounding boxes in one image")
    parser.add_argument("image", help="Path to input image")
    parser.add_argument("--checkpoint", default=None, help="Checkpoint path (default: saved_models/best.pt)")
    parser.add_argument("--output", default=None, help="Annotated image output path")
    parser.add_argument("--config", default=None, help="Path to config.yaml")
    args = parser.parse_args()
    print(json.dumps(predict_image(args.image, args.checkpoint, args.output, args.config), indent=2))


if __name__ == "__main__":
    main()
