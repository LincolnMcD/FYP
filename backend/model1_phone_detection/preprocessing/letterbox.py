"""Aspect-ratio-preserving resize with padding."""

import cv2
import numpy as np


def letterbox(image: np.ndarray, size: int = 640, color: tuple[int, int, int] = (114, 114, 114)):
    """Resize an RGB image into a square canvas and return scale/padding metadata."""
    if image is None or image.ndim != 3 or image.shape[2] != 3:
        raise ValueError("letterbox expects an HxWx3 RGB image")
    height, width = image.shape[:2]
    if min(height, width) <= 0 or size <= 0:
        raise ValueError("Image dimensions and target size must be positive")

    scale = min(size / width, size / height)
    new_width = int(round(width * scale))
    new_height = int(round(height * scale))
    resized = cv2.resize(image, (new_width, new_height), interpolation=cv2.INTER_LINEAR)
    pad_x = (size - new_width) / 2
    pad_y = (size - new_height) / 2
    left, top = int(round(pad_x - 0.1)), int(round(pad_y - 0.1))
    right, bottom = size - new_width - left, size - new_height - top
    output = cv2.copyMakeBorder(resized, top, bottom, left, right, cv2.BORDER_CONSTANT, value=color)
    return output, scale, (left, top)
