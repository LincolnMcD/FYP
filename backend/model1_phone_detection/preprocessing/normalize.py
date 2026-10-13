"""Convert normalized RGB arrays to torch tensors."""

import numpy as np
import torch


def normalize_image(image: np.ndarray) -> torch.Tensor:
    """Convert an RGB image from 0..255 to float CHW in 0..1."""
    if image.ndim != 3 or image.shape[2] != 3:
        raise ValueError("normalize_image expects an HxWx3 RGB image")
    return torch.from_numpy(np.ascontiguousarray(image.transpose(2, 0, 1))).float().div_(255.0)
