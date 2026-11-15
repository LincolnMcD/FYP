"""Run the phone-part detector and return the trade-in API response."""

import json
import sys
from pathlib import Path


def main():
    import torch
    from predict import load_model, predict

    image = Path(sys.argv[1])
    weights = Path(__file__).resolve().parent / "runs" / "phone26n" / "best.pt"
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    if device.type == "cpu":
        torch.set_num_threads(min(torch.get_num_threads(), 4))
    model, checkpoint = load_model(weights, device)
    result = predict(model, image, checkpoint["size"], checkpoint["names"],
                     checkpoint["confidence"], device)
    parts = result["parts"]
    best = max(parts, key=lambda part: part["confidence"], default=None)
    print(json.dumps({
        "success": True,
        "isPhone": best is not None,
        "count": len(parts),
        "category": best["class"] if best else None,
        "confidence": best["confidence"] if best else 0,
        "detections": parts,
        "message": "Smartphone detected successfully." if best else
                   "No smartphone detected in this image."
    }))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"success": False, "isPhone": False, "error": str(error)}))
        sys.exit(1)
