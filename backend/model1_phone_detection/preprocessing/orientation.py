"""EXIF-aware RGB image loading."""

from pathlib import Path

import numpy as np
from PIL import Image, ImageOps


def load_oriented_rgb(path: str | Path) -> np.ndarray:
    """Read an image, apply its EXIF orientation, and return an RGB uint8 array."""
    image_path = Path(path)
    if not image_path.is_file():
        raise FileNotFoundError(f"Image not found: {image_path}")
    try:
        with Image.open(image_path) as image:
            return np.asarray(ImageOps.exif_transpose(image).convert("RGB"))
    except (OSError, ValueError) as exc:
        raise ValueError(f"Could not decode image {image_path}: {exc}") from exc
