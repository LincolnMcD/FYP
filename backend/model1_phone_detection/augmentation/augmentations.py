"""Mild geometric and color augmentation for phone detection."""

import random

import cv2
import numpy as np


def augment(image: np.ndarray, boxes: np.ndarray, config: dict) -> tuple[np.ndarray, np.ndarray]:
    """Apply configured training augmentations and transform normalized xywh boxes."""
    if random.random() < float(config.get("horizontal_flip", 0.5)):
        image = np.ascontiguousarray(image[:, ::-1])
        if len(boxes):
            boxes = boxes.copy()
            boxes[:, 0] = 1.0 - boxes[:, 0]

    height, width = image.shape[:2]
    angle = random.uniform(-float(config.get("rotation_degrees", 10)), float(config.get("rotation_degrees", 10)))
    scale_min, scale_max = config.get("scale_range", [0.9, 1.1])
    scale = random.uniform(float(scale_min), float(scale_max))
    tx = random.uniform(-float(config.get("translation", 0.05)), float(config.get("translation", 0.05))) * width
    ty = random.uniform(-float(config.get("translation", 0.05)), float(config.get("translation", 0.05))) * height
    affine = cv2.getRotationMatrix2D((width / 2, height / 2), angle, scale)
    affine[0, 2] += tx
    affine[1, 2] += ty
    matrix = np.vstack([affine, [0.0, 0.0, 1.0]])
    perspective = float(config.get("perspective", 0.0003))
    if perspective:
        matrix[2, 0] = random.uniform(-perspective, perspective)
        matrix[2, 1] = random.uniform(-perspective, perspective)

    image = cv2.warpPerspective(image, matrix, (width, height), borderValue=(114, 114, 114))
    if len(boxes):
        boxes = _transform_boxes(boxes, matrix, width, height)

    image = _jitter_color(image, config)
    if random.random() < float(config.get("blur_probability", 0.1)):
        image = cv2.GaussianBlur(image, (3, 3), 0)
    return image, boxes


def _transform_boxes(boxes: np.ndarray, matrix: np.ndarray, width: int, height: int) -> np.ndarray:
    """Transform all box corners through a projective matrix and clip to the image."""
    transformed = []
    for cx, cy, bw, bh in boxes:
        x1, y1 = (cx - bw / 2) * width, (cy - bh / 2) * height
        x2, y2 = (cx + bw / 2) * width, (cy + bh / 2) * height
        corners = np.array([[x1, y1, 1], [x2, y1, 1], [x2, y2, 1], [x1, y2, 1]], dtype=np.float32).T
        warped = matrix @ corners
        denominator = np.clip(warped[2], 1e-6, None)
        points = (warped[:2] / denominator).T
        new_x1, new_y1 = points.min(axis=0)
        new_x2, new_y2 = points.max(axis=0)
        new_x1, new_x2 = np.clip([new_x1, new_x2], 0, width)
        new_y1, new_y2 = np.clip([new_y1, new_y2], 0, height)
        if new_x2 > new_x1 and new_y2 > new_y1:
            transformed.append([(new_x1 + new_x2) / (2 * width), (new_y1 + new_y2) / (2 * height),
                                (new_x2 - new_x1) / width, (new_y2 - new_y1) / height])
    return np.asarray(transformed, dtype=np.float32).reshape(-1, 4)


def _jitter_color(image: np.ndarray, config: dict) -> np.ndarray:
    """Apply brightness/exposure and HSV color variation in RGB space."""
    brightness = random.uniform(1 - float(config.get("brightness", 0.15)), 1 + float(config.get("brightness", 0.15)))
    exposure = random.uniform(1 - float(config.get("exposure", 0.15)), 1 + float(config.get("exposure", 0.15)))
    image = np.clip(image.astype(np.float32) * brightness * exposure, 0, 255).astype(np.uint8)
    hsv = cv2.cvtColor(image, cv2.COLOR_RGB2HSV).astype(np.float32)
    hsv[:, :, 0] = (hsv[:, :, 0] + random.uniform(-float(config.get("hsv_hue", 0.015)), float(config.get("hsv_hue", 0.015))) * 180) % 180
    hsv[:, :, 1] *= random.uniform(1 - float(config.get("hsv_saturation", 0.25)), 1 + float(config.get("hsv_saturation", 0.25)))
    hsv[:, :, 2] *= random.uniform(1 - float(config.get("hsv_value", 0.20)), 1 + float(config.get("hsv_value", 0.20)))
    return cv2.cvtColor(np.clip(hsv, 0, 255).astype(np.uint8), cv2.COLOR_HSV2RGB)
