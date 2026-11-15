"""Read the existing YOLO annotations and create reproducible image splits."""

import hashlib
import math
import random
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageOps
import torch
from torch.utils.data import Dataset
import yaml


@dataclass
class Example:
    path: Path
    rows: list
    group: str
    byte_size: int


def read_examples(root):
    with (root / "Phone/data.yaml").open(encoding="utf-8") as handle:
        config = yaml.safe_load(handle)
    names = config["names"]
    if len(names) != config["nc"] or len(set(names)) != len(names):
        raise ValueError("Invalid class names in Phone/data.yaml")
    examples, excluded = [], []
    for folder, labels, positive in [("Phone", "labels", True), ("Non Phone", "label", False)]:
        image_dir = root / folder / "images"
        for image in sorted(image_dir.iterdir()):
            if image.suffix.lower() not in {".jpg", ".jpeg", ".png", ".webp", ".bmp"}:
                continue
            label = root / folder / labels / f"{image.stem}.txt"
            rows = []
            for row in label.read_text(encoding="utf-8-sig").splitlines():
                if not row.strip():
                    continue
                cls, *box = row.split()
                cls, box = int(cls), list(map(float, box))
                if not all(math.isfinite(x) and 0 <= x <= 1 for x in box) or not 0 <= cls < len(names):
                    raise ValueError(f"Invalid normalized YOLO annotation in {label}")
                if len(box) >= 6 and len(box) % 2 == 0:
                    xs, ys = box[::2], box[1::2]
                    x1, x2, y1, y2 = min(xs), max(xs), min(ys), max(ys)
                    box = [(x1 + x2) / 2, (y1 + y2) / 2, x2 - x1, y2 - y1]
                if len(box) != 4 or min(box[2:]) <= 0:
                    raise ValueError(f"Invalid YOLO box or polygon in {label}")
                rows.append((cls, *box))
            if bool(rows) != positive:
                raise ValueError(f"Folder and annotation disagree: {label}")
            if len(rows) > 2 or len({row[0] for row in rows}) != len(rows):
                excluded.append(str(label.relative_to(root)))
                continue
            group = image.stem.casefold().split(".rf.", 1)[0]
            examples.append(Example(image, rows, f"{folder}/{group}", image.stat().st_size))
    return names, examples, excluded


def split_examples(examples, seed):
    # Group both Roboflow variants of the same source and byte-identical files.
    parents = {}

    def representative(key):
        while key in parents:
            key = parents[key]
        return key

    sizes = Counter(item.byte_size for item in examples)
    for item in examples:
        if sizes[item.byte_size] == 1:
            continue
        digest = hashlib.sha256(item.path.read_bytes()).digest()
        name, digest = representative(item.group), representative(digest)
        if name != digest:
            parents[digest] = name
    groups = defaultdict(list)
    for item in examples:
        groups[representative(item.group)].append(item)
    strata = defaultdict(list)
    for group in groups.values():
        kinds = {bool(item.rows) for item in group}
        if len(kinds) != 1:
            raise ValueError(f"Conflicting phone/non-phone labels for {group[0].path}")
        strata[kinds.pop()].append(group)

    rng = random.Random(seed)
    splits = {key: [] for key in ("train", "val", "test")}
    for groups in strata.values():
        rng.shuffle(groups)
        size = sum(map(len, groups))
        counts = dict.fromkeys(splits, 0)
        limits = {"train": size * 0.8, "val": size * 0.1, "test": size * 0.1}
        for group in groups:
            split = min(splits, key=lambda key: counts[key] / limits[key])
            splits[split].extend(group)
            counts[split] += len(group)
    for items in splits.values():
        rng.shuffle(items)
    return splits


def letterbox_canvas(path, size):
    with Image.open(path) as source:
        image = ImageOps.exif_transpose(source).convert("RGB")
    width, height = image.size
    scale = size / max(width, height)
    new_width, new_height = max(1, round(width * scale)), max(1, round(height * scale))
    left, top = (size - new_width) // 2, (size - new_height) // 2
    canvas = Image.new("RGB", (size, size), (114, 114, 114))
    canvas.paste(image.resize((new_width, new_height), Image.Resampling.BILINEAR), (left, top))
    return canvas, (width, height, new_width, new_height, left, top)


def letterbox(path, size):
    canvas, geometry = letterbox_canvas(path, size)
    return torch.from_numpy(np.array(canvas)).permute(2, 0, 1), geometry


def rotate_and_zoom(image, target, angle, scale):
    size = image.width
    center = size / 2
    radians = math.radians(angle)
    cosine, sine = math.cos(radians), math.sin(radians)
    if len(target):
        cls, x1, y1, x2, y2 = target.unbind(dim=1)
        xs = torch.stack((x1, x2, x2, x1), dim=1) - center
        ys = torch.stack((y1, y1, y2, y2), dim=1) - center
        rotated_x = scale * (cosine * xs + sine * ys) + center
        rotated_y = scale * (-sine * xs + cosine * ys) + center
        boxes = torch.stack((rotated_x.amin(1), rotated_y.amin(1),
                             rotated_x.amax(1), rotated_y.amax(1)), dim=1)
        clipped = boxes.clamp(0, size)
        area = (boxes[:, 2:] - boxes[:, :2]).prod(dim=1)
        clipped_area = (clipped[:, 2:] - clipped[:, :2]).prod(dim=1)
        if (clipped_area < 0.90 * area).any():
            return image, target
        target = torch.cat((cls[:, None], clipped), dim=1)

    # Pillow samples each output pixel from its inverse-mapped source location.
    a, b = cosine / scale, sine / scale
    inverse = (a, -b, center * (1 - a + b), b, a, center * (1 - a - b))
    image = image.transform(image.size, Image.Transform.AFFINE, inverse,
                            resample=Image.Resampling.BILINEAR, fillcolor=(114, 114, 114))
    return image, target


def horizontal_flip(image, target, flip_classes):
    left, right = flip_classes
    cls, x1, y1, x2, y2 = target.unbind(dim=1)
    mirrored_cls = torch.where(cls == left, right, torch.where(cls == right, left, cls))
    mirrored_target = torch.stack((mirrored_cls, image.width - x2, y1, image.width - x1, y2), dim=1)
    return ImageOps.mirror(image), mirrored_target


def augment_image(image, target, flip_classes):
    if flip_classes is not None and random.random() < 0.5:
        image, target = horizontal_flip(image, target, flip_classes)
    if random.random() < 0.8:
        image, target = rotate_and_zoom(image, target, random.uniform(-15, 15), random.uniform(0.92, 1.08))
    for enhancer, amount in ((ImageEnhance.Brightness, 0.15),
                             (ImageEnhance.Contrast, 0.12),
                             (ImageEnhance.Color, 0.12)):
        if random.random() < 0.7:
            image = enhancer(image).enhance(random.uniform(1 - amount, 1 + amount))
    return image, target


class PhoneDataset(Dataset):
    def __init__(self, examples, size, augment=False, flip_classes=None):
        self.examples = examples
        self.size = size
        self.augment = augment
        self.flip_classes = flip_classes

    def __len__(self):
        return len(self.examples)

    def __getitem__(self, index):
        example = self.examples[index]
        image, (_, _, width, height, left, top) = letterbox_canvas(example.path, self.size)
        target = torch.tensor(example.rows, dtype=torch.float32).reshape(-1, 5)
        cls, x, y, w, h = target.unbind(dim=1)
        target = torch.stack((cls, (x - w / 2).clamp(0, 1) * width + left,
                              (y - h / 2).clamp(0, 1) * height + top,
                              (x + w / 2).clamp(0, 1) * width + left,
                              (y + h / 2).clamp(0, 1) * height + top), dim=1)
        region = (left, top, left + width, top + height)
        if self.augment:
            image, target = augment_image(image, target, self.flip_classes)
            region = (0, 0, self.size, self.size)
        tensor = torch.from_numpy(np.array(image)).permute(2, 0, 1)
        return tensor, target, region


def collate(batch):
    images, targets, regions = zip(*batch)
    return torch.stack(images), targets, torch.tensor(regions)
