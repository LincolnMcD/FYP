"""Target assignment, training loss, and bounded end-to-end inference."""

import math

import torch
from torch.nn import functional as F

from yolo26 import decode


def iou(a, b):
    intersection = (torch.minimum(a[..., 2:], b[..., 2:])
                    - torch.maximum(a[..., :2], b[..., :2])).clamp_min(0).prod(dim=-1)
    area_a = (a[..., 2:] - a[..., :2]).clamp_min(0).prod(dim=-1)
    area_b = (b[..., 2:] - b[..., :2]).clamp_min(0).prod(dim=-1)
    return intersection / (area_a + area_b - intersection).clamp_min(1e-7)


def complete_iou(a, b):
    overlap = iou(a, b)
    center_distance = ((a[..., :2] + a[..., 2:] - b[..., :2] - b[..., 2:]) / 2).square().sum(-1)
    diagonal = (torch.maximum(a[..., 2:], b[..., 2:])
                - torch.minimum(a[..., :2], b[..., :2])).square().sum(-1).clamp_min(1e-7)
    aw, ah = (a[..., 2:] - a[..., :2]).clamp_min(1e-7).unbind(-1)
    bw, bh = (b[..., 2:] - b[..., :2]).clamp_min(1e-7).unbind(-1)
    aspect = 4 / math.pi**2 * (torch.atan(aw / ah) - torch.atan(bw / bh)).square()
    weight = (aspect / (1 - overlap + aspect + 1e-7)).detach()
    return overlap - center_distance / diagonal - weight * aspect


def pack_targets(targets, device):
    packed = torch.full((len(targets), 2, 5), -1.0)
    for index, target in enumerate(targets):
        packed[index, :len(target)] = target
    return packed.to(device)


@torch.no_grad()
def assign(boxes, logits, points, targets, top_k):
    labels = targets[..., 0].long()
    gt = targets[..., 1:]
    overlap = iou(gt[:, :, None], boxes[:, None])
    inside = ((points >= gt[:, :, None, :2]) & (points <= gt[:, :, None, 2:])).all(-1)
    class_scores = logits.sigmoid().transpose(1, 2).gather(
        1, labels.clamp_min(0)[..., None].expand(-1, -1, logits.size(1)))
    center_distance = (points - ((gt[..., :2] + gt[..., 2:]) / 2)[:, :, None]).square().sum(-1)
    # Very small boxes can fall between grid centers. Give them a nearest-center candidate.
    nearest = torch.zeros_like(inside).scatter_(-1, center_distance.argmin(-1, keepdim=True), True)
    candidates = torch.where(inside.any(-1, keepdim=True), inside, nearest)
    candidates &= labels[..., None] >= 0
    alignment = class_scores.sqrt() * overlap.pow(6) + 1e-9 / (1 + center_distance)
    alignment = alignment.masked_fill(~candidates, -1)
    if top_k == 1:
        # Assign the strongest match first, then reserve a distinct anchor for the other target.
        best = alignment.argmax(-1, keepdim=True)
        first = alignment.amax(-1).argmax(-1)
        batch = torch.arange(len(boxes), device=boxes.device)
        anchor = best[batch, first, 0]
        other = 1 - first
        remaining = alignment[batch, other].clone()
        remaining[batch, anchor] = -1
        best[batch, other, 0] = remaining.argmax(-1)
        candidates = candidates.clone()
        candidates[batch, other, anchor] = False
    else:
        best = alignment.topk(min(top_k, len(points)), dim=-1).indices
    selected = torch.zeros_like(candidates).scatter_(-1, best, True) & candidates
    foreground = selected.any(1)
    owner = overlap.masked_fill(~selected, -1).argmax(1)
    gt_boxes = gt.gather(1, owner[..., None].expand(-1, -1, 4))
    gt_labels = labels.gather(1, owner).clamp_min(0)
    quality = overlap.gather(1, owner[:, None]).squeeze(1).clamp_min(0.05) * foreground
    class_targets = torch.zeros_like(logits).scatter_(-1, gt_labels[..., None], quality[..., None])
    return gt_boxes, class_targets, foreground, quality


def branch_loss(branch, points, strides, targets, top_k):
    distances, logits = branch
    logits = logits.float()
    boxes = decode(distances, points, strides)
    gt, classes, foreground, quality = assign(boxes.detach(), logits.detach(), points, targets, top_k)
    normalizer = quality.sum().clamp_min(1)
    classification = F.binary_cross_entropy_with_logits(logits, classes, reduction="sum") / normalizer
    matched, gt = boxes[foreground], gt[foreground]
    weight = quality[foreground]
    localization = ((1 - complete_iou(matched, gt)) * weight).sum() / normalizer
    distance = (matched - gt).abs() / strides.expand(boxes.shape[0], -1, -1)[foreground]
    l1 = (distance.mean(-1) * weight).sum() / normalizer
    return 0.5 * classification + 7.5 * localization + 1.5 * l1


def training_loss(output, targets, progress):
    one, many, points, strides = output
    many_weight = 0.8 - 0.7 * progress
    return ((1 - many_weight) * branch_loss(one, points, strides, targets, 1)
            + many_weight * branch_loss(many, points, strides, targets, 10))


def detections(output, regions):
    (distances, logits), _, points, strides = output
    boxes = decode(distances, points, strides)
    lower = regions[:, None, :2].repeat(1, 1, 2)
    upper = regions[:, None, 2:].repeat(1, 1, 2)
    boxes = torch.maximum(torch.minimum(boxes, upper), lower)
    valid = (boxes[..., 2:] > boxes[..., :2]).all(-1)
    # One class per anchor, then the strongest anchor for each distinct class.
    scores, classes = logits.float().sigmoid().max(dim=-1)
    mask = classes[..., None] == torch.arange(logits.shape[-1], device=classes.device)
    class_scores, anchors = scores[..., None].masked_fill(~(mask & valid[..., None]), -1).max(dim=1)
    scores, classes = class_scores.topk(min(2, logits.shape[-1]), dim=-1)
    anchors = anchors.gather(1, classes)
    boxes = boxes.gather(1, anchors[..., None].expand(-1, -1, 4))
    return torch.cat((boxes, scores[..., None], classes[..., None]), dim=-1)
