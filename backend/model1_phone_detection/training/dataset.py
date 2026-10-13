"""YOLO-format image dataset with deterministic stratified split support."""

from pathlib import Path
import random

import numpy as np
import torch
from torch.utils.data import Dataset

from augmentation.augmentations import augment
from preprocessing.letterbox import letterbox
from preprocessing.normalize import normalize_image
from preprocessing.orientation import load_oriented_rgb


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def _image_files(folder: Path) -> list[Path]:
    if not folder.is_dir():
        raise FileNotFoundError(f"Image folder not found: {folder}")
    return sorted(path for path in folder.iterdir() if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS)


def _label_directory(class_dir: Path) -> Path | None:
    for name in ("labels", "label"):
        candidate = class_dir / name
        if candidate.is_dir():
            return candidate
    return None


def collect_samples(root: str | Path) -> list[dict]:
    """Read Phone and Non Phone image paths and pair available YOLO label files."""
    root = Path(root)
    samples = []
    for folder_name, is_phone in (("Phone", True), ("Non Phone", False)):
        class_dir = root / folder_name
        image_dir = class_dir / "images"
        if not image_dir.is_dir():
            raise FileNotFoundError(f"Expected dataset folder: {image_dir}")
        label_dir = _label_directory(class_dir)
        if is_phone and label_dir is None:
            raise FileNotFoundError(f"Phone labels folder not found under {class_dir} (expected labels/ or label/)")
        for image_path in _image_files(image_dir):
            label_path = (label_dir / f"{image_path.stem}.txt") if label_dir else None
            if is_phone and (label_path is None or not label_path.is_file()):
                raise FileNotFoundError(f"Phone image is missing its label: {image_path}")
            samples.append({"image": image_path, "label": label_path, "has_phone": is_phone})
    if not samples:
        raise ValueError(f"No supported images found under {root}")
    if not any(sample["has_phone"] for sample in samples):
        raise ValueError("The dataset contains no Phone images")
    return samples


def split_samples(samples: list[dict], train: float = 0.7, val: float = 0.15, test: float = 0.15,
                  seed: int = 42) -> tuple[list[dict], list[dict], list[dict]]:
    """Split phone and negative images separately so each split is stratified."""
    ratios = [float(train), float(val), float(test)]
    if any(ratio < 0 for ratio in ratios) or abs(sum(ratios) - 1.0) > 1e-6:
        raise ValueError("Train, validation, and test fractions must be nonnegative and sum to 1")
    rng = random.Random(seed)
    results = [[], [], []]
    for phone_group in (False, True):
        group = [sample for sample in samples if sample["has_phone"] is phone_group]
        rng.shuffle(group)
        n_train = int(len(group) * ratios[0])
        n_val = int(len(group) * ratios[1])
        if len(group) >= 3:
            n_train = max(1, n_train)
            n_val = max(1, n_val)
        allocations = (group[:n_train], group[n_train:n_train + n_val], group[n_train + n_val:])
        for result, subset in zip(results, allocations):
            result.extend(subset)
    for result in results:
        rng.shuffle(result)
    if not all(results):
        raise ValueError("A split is empty; add data or adjust the split fractions")
    return tuple(results)


def limit_samples(samples: list[dict], maximum: int | None, seed: int = 42) -> list[dict]:
    """Return a deterministic, approximately class-balanced subset for smoke runs."""
    if maximum is None or maximum >= len(samples):
        return samples
    if maximum <= 0:
        raise ValueError("Image limits must be positive")
    rng = random.Random(seed)
    phones = [sample for sample in samples if sample["has_phone"]]
    negatives = [sample for sample in samples if not sample["has_phone"]]
    if maximum >= 2 and phones and negatives:
        phone_count = round(maximum * len(phones) / len(samples))
        phone_count = min(max(len(phones), 1), max(1, phone_count))
        phone_count = min(phone_count, maximum - 1)
        negative_count = maximum - phone_count
        if negative_count > len(negatives):
            phone_count += negative_count - len(negatives)
            negative_count = len(negatives)
        selected = rng.sample(phones, min(phone_count, len(phones)))
        selected += rng.sample(negatives, min(negative_count, len(negatives)))
    else:
        selected = rng.sample(samples, maximum)
    rng.shuffle(selected)
    return selected


def balanced_diagnostic_samples(samples: list[dict], maximum: int, seed: int = 42) -> list[dict]:
    """Sample equally from each class without duplicating images."""
    rng = random.Random(seed)
    phones = [sample for sample in samples if sample["has_phone"]]
    negatives = [sample for sample in samples if not sample["has_phone"]]
    phone_count, negative_count = (maximum + 1) // 2, maximum // 2
    if len(phones) < phone_count or len(negatives) < negative_count:
        raise ValueError("Not enough images of each class for the balanced diagnostic; reduce --overfit-images")
    selected = rng.sample(phones, phone_count) + rng.sample(negatives, negative_count)
    rng.shuffle(selected)
    return selected


def limit_class_samples(samples: list[dict], max_phone: int | None = None,
                        max_non_phone: int | None = None, seed: int = 42) -> list[dict]:
    """Cap Phone and Non Phone counts independently using reproducible sampling."""
    rng = random.Random(seed)
    selected = []
    for is_phone, maximum in ((True, max_phone), (False, max_non_phone)):
        group = [sample for sample in samples if sample["has_phone"] is is_phone]
        if maximum is not None:
            maximum = int(maximum)
            if maximum <= 0:
                raise ValueError("Per-folder image limits must be positive")
            if len(group) > maximum:
                group = rng.sample(group, maximum)
        selected.extend(group)
    rng.shuffle(selected)
    return selected


class PhoneDataset(Dataset):
    """Return letterboxed image tensors and normalized phone xywh targets."""

    def __init__(self, samples: list[dict], image_size: int = 640, training: bool = False,
                 augmentation_config: dict | None = None):
        self.samples = samples
        self.image_size = int(image_size)
        self.training = training
        self.augmentation_config = augmentation_config or {}

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, index: int):
        sample = self.samples[index]
        image = load_oriented_rgb(sample["image"])
        boxes = self._read_boxes(sample)
        if self.training and self.augmentation_config.get("enabled", True):
            image, boxes = augment(image, boxes, self.augmentation_config)

        original_h, original_w = image.shape[:2]
        image, scale, (pad_x, pad_y) = letterbox(image, self.image_size)
        if len(boxes):
            boxes = boxes.copy()
            boxes[:, 0] = (boxes[:, 0] * original_w * scale + pad_x) / self.image_size
            boxes[:, 1] = (boxes[:, 1] * original_h * scale + pad_y) / self.image_size
            boxes[:, 2] = boxes[:, 2] * original_w * scale / self.image_size
            boxes[:, 3] = boxes[:, 3] * original_h * scale / self.image_size
        return normalize_image(image), torch.from_numpy(boxes.astype(np.float32)), sample["image"].name

    @staticmethod
    def _read_boxes(sample: dict) -> np.ndarray:
        """Read normalized YOLO rows. All phone folder rows map to class 0."""
        if not sample["has_phone"]:
            return np.empty((0, 4), dtype=np.float32)
        boxes = []
        label_path = sample["label"]
        try:
            lines = label_path.read_text(encoding="utf-8").splitlines()
        except OSError as exc:
            raise OSError(f"Could not read label file {label_path}: {exc}") from exc
        for line_number, line in enumerate(lines, 1):
            if not line.strip():
                continue
            values = line.split()
            if len(values) < 5:
                raise ValueError(f"Malformed YOLO label at {label_path}:{line_number}")
            try:
                int(values[0])
                coords = [float(value) for value in values[1:5]]
            except ValueError as exc:
                raise ValueError(f"Non-numeric YOLO label at {label_path}:{line_number}") from exc
            if any(value < 0 or value > 1 for value in coords) or coords[2] <= 0 or coords[3] <= 0:
                raise ValueError(f"YOLO coordinates must be normalized and have positive size at {label_path}:{line_number}")
            boxes.append(coords)
        return np.asarray(boxes, dtype=np.float32).reshape(-1, 4)


def detection_collate(batch):
    """Stack images while retaining variable-length target lists and filenames."""
    images, boxes, names = zip(*batch)
    return torch.stack(images), list(boxes), list(names)


def build_datasets(config: dict):
    """Build train, validation, and test sets from configured roots or a random split."""
    dataset_config = config["dataset"]
    split_keys = ("train_path", "val_path", "test_path")
    explicit = [dataset_config.get(key) for key in split_keys]
    if any(explicit) and not all(explicit):
        raise ValueError("Set all three dataset train_path, val_path, and test_path values, or leave all null")
    if all(explicit):
        train_samples, val_samples, test_samples = [
            limit_class_samples(
                collect_samples(path), dataset_config.get("max_phone_images"),
                dataset_config.get("max_non_phone_images"), config.get("seed", 42) + index,
            )
            for index, path in enumerate(explicit)
        ]
    else:
        samples = collect_samples(dataset_config["root"])
        samples = limit_class_samples(
            samples, dataset_config.get("max_phone_images"),
            dataset_config.get("max_non_phone_images"), config.get("seed", 42),
        )
        train_samples, val_samples, test_samples = split_samples(
            samples,
            dataset_config.get("train_fraction", 0.7),
            dataset_config.get("val_fraction", 0.15),
            dataset_config.get("test_fraction", 0.15),
            config.get("seed", 42),
        )
    image_size = config.get("image_size", 640)
    augmentation = config.get("augmentation", {})
    return (
        PhoneDataset(train_samples, image_size, True, augmentation),
        PhoneDataset(val_samples, image_size, False),
        PhoneDataset(test_samples, image_size, False),
    )
