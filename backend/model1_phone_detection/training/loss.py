"""Anchor-free focal classification and CIoU box regression loss."""

import torch
import torch.nn.functional as F


def configured_detection_loss(outputs, targets, config):
    """Use identical loss settings in training, evaluation, and diagnostics."""
    settings = config.get("loss", {})
    defaults = dict(classification_weight=1.0, box_weight=5.0, assign_topk=5,
                    focal_alpha=0.25, focal_gamma=2.0, negative_weight=0.25,
                    assignment_alpha=0.5, assignment_beta=6.0,
                    classification_mode="focal", hard_negative_ratio=3,
                    classification_target="soft", negative_mining="batch")
    return detection_loss(outputs, targets, int(config.get("image_size", 640)),
                          **{key: settings.get(key, value) for key, value in defaults.items()})


def _per_image_hard_negative_loss(element_loss, positive_mask, ratio):
    """Give every image its own quota and equal weight in background loss."""
    image_losses = []
    for losses, positives in zip(element_loss, positive_mask):
        negatives = losses[~positives]
        if negatives.numel():
            count = min(negatives.numel(), ratio * max(int(positives.sum()), 1))
            image_losses.append(negatives.topk(count).values.mean())
        else:
            image_losses.append(losses.sum() * 0.0)
    return torch.stack(image_losses).mean()


def _ciou_xywh(box_a: torch.Tensor, box_b: torch.Tensor) -> torch.Tensor:
    """Compute pairwise CIoU for matching (..., 4) normalized xywh boxes."""
    eps = 1e-7
    a_min, a_max = box_a[..., :2] - box_a[..., 2:] / 2, box_a[..., :2] + box_a[..., 2:] / 2
    b_min, b_max = box_b[..., :2] - box_b[..., 2:] / 2, box_b[..., :2] + box_b[..., 2:] / 2
    intersection = (torch.minimum(a_max, b_max) - torch.maximum(a_min, b_min)).clamp(min=0).prod(dim=-1)
    area_a = (a_max - a_min).clamp(min=0).prod(dim=-1)
    area_b = (b_max - b_min).clamp(min=0).prod(dim=-1)
    iou = intersection / (area_a + area_b - intersection + eps)

    center_distance = ((box_a[..., :2] - box_b[..., :2]) ** 2).sum(dim=-1)
    enclosing_min = torch.minimum(a_min, b_min)
    enclosing_max = torch.maximum(a_max, b_max)
    diagonal = ((enclosing_max - enclosing_min) ** 2).sum(dim=-1) + eps
    aspect = (4.0 / (torch.pi ** 2)) * (
        torch.atan(box_b[..., 2] / (box_b[..., 3] + eps)) - torch.atan(box_a[..., 2] / (box_a[..., 3] + eps))
    ) ** 2
    alpha = aspect / (1.0 - iou + aspect + eps)
    return iou - center_distance / diagonal - alpha * aspect


def _assigned_box_loss(box_logits, assignments):
    """Gather/decode all positives at one level and regress them together."""
    if not assignments:
        return box_logits.sum() * 0.0
    _, _, height, width = box_logits.shape
    indices = torch.tensor([entry[:3] for entry in assignments], device=box_logits.device, dtype=torch.long)
    batch_indices, gy, gx = indices.unbind(dim=1)
    raw = box_logits[batch_indices, :, gy, gx]
    offsets = 0.5 + 1.5 * torch.tanh(raw[:, :2])
    sizes = torch.sigmoid(raw[:, 2:])
    centers = torch.stack(((gx.to(raw.dtype) + offsets[:, 0]) / width,
                           (gy.to(raw.dtype) + offsets[:, 1]) / height), dim=1)
    predictions = torch.cat((centers, sizes), dim=1)
    targets = torch.stack([entry[3] for entry in assignments]).to(box_logits.device)
    return (1.0 - _ciou_xywh(predictions, targets)).mean()


def _decode_level_boxes(box_logits: torch.Tensor) -> torch.Tensor:
    """Decode one feature level to normalized xywh boxes for assignment."""
    batch_size, _, height, width = box_logits.shape
    yy, xx = torch.meshgrid(
        torch.arange(height, device=box_logits.device, dtype=box_logits.dtype),
        torch.arange(width, device=box_logits.device, dtype=box_logits.dtype),
        indexing="ij",
    )
    offsets = 0.5 + 1.5 * torch.tanh(box_logits[:, :2])
    centers_x = (xx[None] + offsets[:, 0]) / width
    centers_y = (yy[None] + offsets[:, 1]) / height
    sizes = torch.sigmoid(box_logits[:, 2:])
    return torch.stack((centers_x, centers_y, sizes[:, 0], sizes[:, 1]), dim=-1).reshape(batch_size, -1, 4)


def _iou_with_target(boxes: torch.Tensor, target: torch.Tensor) -> torch.Tensor:
    """Vectorized IoU between normalized xywh candidates and one target box."""
    boxes_min, boxes_max = boxes[:, :2] - boxes[:, 2:] / 2, boxes[:, :2] + boxes[:, 2:] / 2
    target_min, target_max = target[:2] - target[2:] / 2, target[:2] + target[2:] / 2
    intersection = (torch.minimum(boxes_max, target_max) - torch.maximum(boxes_min, target_min))
    intersection = intersection.clamp(min=0).prod(dim=1)
    box_area = boxes[:, 2:].clamp(min=0).prod(dim=1)
    target_area = target[2:].clamp(min=0).prod()
    return intersection / (box_area + target_area - intersection + 1e-7)


def detection_loss(outputs, targets: list[torch.Tensor], image_size: int = 640,
                   classification_weight: float = 1.0, box_weight: float = 5.0,
                   assign_topk: int = 5, focal_alpha: float = 0.25,
                   focal_gamma: float = 2.0, negative_weight: float = 0.25,
                   assignment_alpha: float = 0.5, assignment_beta: float = 6.0,
                   classification_mode: str = "focal", hard_negative_ratio: int = 3,
                   classification_target: str = "soft", negative_mining: str = "batch"):
    """Task-align positive cells by predicted class score and box IoU."""
    device = outputs[0][0].device
    if classification_mode not in ("focal", "bce"):
        raise ValueError("classification_mode must be focal or bce")
    if classification_target not in ("binary", "soft"):
        raise ValueError("classification_target must be binary or soft")
    if negative_mining not in ("batch", "per_image"):
        raise ValueError("negative_mining must be batch or per_image")
    if hard_negative_ratio < 1:
        raise ValueError("hard_negative_ratio must be positive")
    cls_losses = []
    box_losses = []

    for level_index, (box_logits, cls_logits) in enumerate(outputs):
        batch_size, _, height, width = box_logits.shape
        class_targets = torch.zeros_like(cls_logits)
        assignments = {}
        with torch.no_grad():
            decoded_boxes = _decode_level_boxes(box_logits.detach())
            class_scores = cls_logits.detach().sigmoid().squeeze(1).flatten(1)
            grid_y, grid_x = torch.meshgrid(
                torch.arange(height, device=device, dtype=box_logits.dtype) + 0.5,
                torch.arange(width, device=device, dtype=box_logits.dtype) + 0.5,
                indexing="ij",
            )
            for batch_index, boxes in enumerate(targets):
                for box in boxes.to(device):
                    side = max(float(box[2]), float(box[3]))
                    target_level = 0 if side < 0.15 else (1 if side < 0.40 else 2)
                    if target_level != level_index:
                        continue

                    center_x, center_y = float(box[0]) * width, float(box[1]) * height
                    # Decoder centers are grid centers + 1.5*tanh(raw).
                    # Strict bounds exclude offsets requiring infinite logits.
                    reachable = ((grid_x - center_x).abs() < 1.5) & ((grid_y - center_y).abs() < 1.5)
                    candidate_indices = reachable.flatten().nonzero(as_tuple=False).squeeze(1)
                    flat_distance = ((grid_x - center_x) ** 2 + (grid_y - center_y) ** 2).flatten()
                    if candidate_indices.numel() == 0:
                        raise ValueError("Ground-truth center is outside the decoder's reachable grid")

                    candidate_boxes = decoded_boxes[batch_index, candidate_indices]
                    candidate_ious = _iou_with_target(candidate_boxes, box)
                    candidate_scores = class_scores[batch_index, candidate_indices]
                    alignment = candidate_scores.pow(assignment_alpha) * candidate_ious.clamp(min=0).pow(assignment_beta)

                    if float(alignment.max()) <= 1e-12:
                        # Warm start: when initial predictions do not overlap GT,
                        # use nearest reachable cells so the box branch can learn to overlap.
                        order = flat_distance[candidate_indices].argsort()
                        selected_local = order[:min(max(1, int(assign_topk)), order.numel())]
                        qualities = torch.ones_like(selected_local, dtype=box_logits.dtype)
                        selected_alignment = -flat_distance[candidate_indices[selected_local]]
                    else:
                        count = min(max(1, int(assign_topk)), candidate_indices.numel())
                        selected_alignment, selected_local = alignment.topk(count)
                        max_alignment = alignment.max().clamp(min=1e-12)
                        max_iou = candidate_ious[selected_local].max()
                        qualities = (selected_alignment / max_alignment) * max_iou
                        qualities = qualities.clamp(min=0.05, max=1.0)

                    for local_index, quality, alignment_score in zip(
                        selected_local.tolist(), qualities, selected_alignment
                    ):
                        flat_index = int(candidate_indices[local_index])
                        gy, gx = divmod(flat_index, width)
                        distance = float(flat_distance[flat_index])
                        key = (batch_index, gy, gx)
                        current = assignments.get(key)
                        score = float(alignment_score)
                        if current is None or score > current[2] or (score == current[2] and distance < current[3]):
                            assignments[key] = (box, quality, score, distance)

        positive_indices = []
        for (batch_index, gy, gx), (box, quality, _, _) in assignments.items():
            # Binary supervision stays at 1 in both warm-start and aligned
            # assignment, independently of the current regression quality.
            class_targets[batch_index, :, gy, gx] = 1.0 if classification_target == "binary" else quality
            positive_indices.append((batch_index, gy, gx, box))

        cls_bce = F.binary_cross_entropy_with_logits(cls_logits, class_targets, reduction="none")
        probabilities = torch.sigmoid(cls_logits)
        p_t = probabilities * class_targets + (1.0 - probabilities) * (1.0 - class_targets)
        alpha_t = focal_alpha * class_targets + (1.0 - focal_alpha) * (1.0 - class_targets)
        focal_loss = alpha_t * (1.0 - p_t).pow(focal_gamma) * cls_bce
        positive_mask = class_targets > 0
        negative_mask = ~positive_mask
        element_loss = cls_bce if classification_mode == "bce" else focal_loss
        positive_loss = element_loss[positive_mask].mean() if positive_mask.any() else cls_logits.sum() * 0.0
        negatives = element_loss[negative_mask]
        if classification_mode == "bce" and negative_mining == "per_image":
            negative_loss = _per_image_hard_negative_loss(element_loss, positive_mask, hard_negative_ratio)
        elif classification_mode == "bce" and negatives.numel():
            # Hard-negative mining avoids diluting confident background errors
            # among thousands of easy negatives; bound the loss on empty images.
            count = min(negatives.numel(), hard_negative_ratio * max(int(positive_mask.sum()), batch_size))
            negatives = negatives.topk(count).values
            negative_loss = negatives.mean()
        else:
            negative_loss = negatives.mean() if negatives.numel() else cls_logits.sum() * 0.0
        cls_losses.append(positive_loss + negative_weight * negative_loss)
        box_losses.append(_assigned_box_loss(box_logits, positive_indices))

    cls_loss = torch.stack(cls_losses).mean()
    box_loss = torch.stack(box_losses).mean()
    total = classification_weight * cls_loss + box_weight * box_loss
    return total, {"classification": cls_loss.detach(), "box": box_loss.detach()}
