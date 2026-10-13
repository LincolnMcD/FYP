"""
Fast CLI interface for Model 1 Phone Detection.
Takes an image path as argument, runs predict_image(), and prints a JSON result.
"""
import sys
import json
import os
from pathlib import Path

# Set working directory to this script's directory so relative imports work
SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

try:
    from inference.predict import predict_image
except ImportError as e:
    # If called from root
    from model1_phone_detection.inference.predict import predict_image

def get_default_checkpoint():
    for candidate in (
        SCRIPT_DIR / "saved_models" / "resnet18" / "best.pt",
        SCRIPT_DIR / "best.pt",
        SCRIPT_DIR / "saved_models" / "best.pt"
    ):
        if candidate.is_file():
            return candidate
    return SCRIPT_DIR / "saved_models" / "best.pt"

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"success": False, "error": "No image path provided."}))
        sys.exit(1)

    image_path = Path(sys.argv[1]).resolve()
    if not image_path.is_file():
        print(json.dumps({"success": False, "error": f"Image file not found: {image_path}"}))
        sys.exit(1)

    checkpoint_path = get_default_checkpoint()
    config_path = SCRIPT_DIR / "config" / "config.yaml"

    try:
        result = predict_image(
            image_path=image_path,
            checkpoint_path=checkpoint_path,
            config_path=config_path,
            output_path=None,
            save_annotated=False
        )

        detections = result.get("detections", [])
        is_phone = len(detections) > 0
        top_confidence = detections[0]["confidence"] if is_phone else 0.0

        output = {
            "success": True,
            "isPhone": is_phone,
            "count": len(detections),
            "confidence": round(top_confidence, 4),
            "detections": detections,
            "message": "Smartphone detected successfully." if is_phone else "No smartphone detected in this image."
        }
        print(json.dumps(output))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e), "isPhone": False}))
        sys.exit(1)

if __name__ == "__main__":
    main()
