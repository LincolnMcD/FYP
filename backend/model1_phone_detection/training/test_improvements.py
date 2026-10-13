"""Regression checks for diagnostic sampling, loss, and BatchNorm inspection."""

import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

import torch

from training.dataset import balanced_diagnostic_samples
from training.diagnostics import compare_batchnorm_modes, save_prediction_overlays
from training.loss import configured_detection_loss, _per_image_hard_negative_loss
from training.scheduler import build_optimizer


class ToyDetector(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.bn = torch.nn.BatchNorm2d(3)
        self.head = torch.nn.Conv2d(3, 5, 1)

    def forward(self, images):
        logits = self.head(self.bn(images))
        return [(logits[:, :4], logits[:, 4:])]


class ImprovementTests(unittest.TestCase):
    def test_warmup_cosine_rates_and_resume(self):
        config = {"learning_rate": .0003, "epochs": 100,
                  "optimizer": {"warmup_epochs": 5, "warmup_start_factor": .1, "min_learning_rate": .00001}}
        model = torch.nn.Linear(1, 1)
        optimizer, scheduler = build_optimizer(model, config)
        rates = []
        for epoch in range(101):
            rates.append(optimizer.param_groups[0]["lr"])
            if epoch == 3:
                optimizer_state, scheduler_state = optimizer.state_dict(), scheduler.state_dict()
                other_optimizer, other_scheduler = build_optimizer(torch.nn.Linear(1, 1), config)
                other_optimizer.load_state_dict(optimizer_state)
                other_scheduler.load_state_dict(scheduler_state)
                other_optimizer.step()
                other_scheduler.step()
                resumed_rate = other_optimizer.param_groups[0]["lr"]
            optimizer.step()
            scheduler.step()
        self.assertAlmostEqual(rates[0], .00003)
        self.assertAlmostEqual(rates[5], .0003)
        self.assertAlmostEqual(rates[100], .00001)
        self.assertAlmostEqual(rates[4], resumed_rate)
        self.assertTrue(all(a < b for a, b in zip(rates[:5], rates[1:6])))
        self.assertTrue(all(a >= b for a, b in zip(rates[5:100], rates[6:101])))

    def test_short_run_scheduler_is_valid(self):
        for epochs in (1, 2, 3):
            optimizer, scheduler = build_optimizer(torch.nn.Linear(1, 1), {
                "learning_rate": .0003, "epochs": epochs, "optimizer": {"warmup_epochs": 5}})
            for _ in range(epochs):
                self.assertGreater(optimizer.param_groups[0]["lr"], 0)
                optimizer.step()
                scheduler.step()
            self.assertAlmostEqual(optimizer.param_groups[0]["lr"], .00001)

    def test_each_image_receives_its_own_negative_quota(self):
        # A harder first image must not consume the second image's quota.
        losses = torch.tensor([[10., 9., 8., 7.], [4., 3., 2., 1.]], requires_grad=True)
        mask = torch.zeros_like(losses, dtype=torch.bool)
        loss = _per_image_hard_negative_loss(losses, mask, 2)
        self.assertAlmostEqual(float(loss.detach()), 6.5)
        loss.backward()
        self.assertTrue(torch.equal(losses.grad, torch.tensor([[.25, .25, 0., 0.], [.25, .25, 0., 0.]])))

    def test_negative_quota_uses_image_positive_count_and_handles_no_negatives(self):
        losses = torch.tensor([[100., 100., 8., 7., 6., 5.], [4., 3., 2., 1., 0., 0.]], requires_grad=True)
        mask = torch.tensor([[True, True, False, False, False, False], [False]*6])
        loss = _per_image_hard_negative_loss(losses, mask, 2)
        self.assertAlmostEqual(float(loss.detach()), 5.)
        loss.backward()
        self.assertTrue((losses.grad[mask] == 0).all())
        no_negatives = _per_image_hard_negative_loss(losses, torch.ones_like(mask), 3)
        self.assertEqual(float(no_negatives.detach()), 0.)

    def test_background_weight_scales_empty_image_loss(self):
        outputs = [(torch.zeros(2, 4, 8, 8), torch.zeros(2, 1, 8, 8, requires_grad=True))]
        target = [torch.empty(0, 4), torch.empty(0, 4)]
        config = {"loss": {"classification_mode": "bce", "negative_mining": "per_image", "negative_weight": .25}}
        old, _ = configured_detection_loss(outputs, target, config)
        config["loss"]["negative_weight"] = 1.
        new, _ = configured_detection_loss(outputs, target, config)
        self.assertAlmostEqual(float(new.detach()), 4*float(old.detach()))
        new.backward()
        self.assertTrue(torch.isfinite(outputs[0][1].grad).all())

    def test_binary_targets_do_not_switch_with_assignment_iou(self):
        import torch.nn.functional as functional
        original_bce = functional.binary_cross_entropy_with_logits
        for iou in (0.0, 0.10, 0.80):
            scores = torch.zeros(1, 1, 8, 8, requires_grad=True)
            outputs = [(torch.zeros(1, 4, 8, 8, requires_grad=True), scores)]
            targets = [torch.tensor([[.51, .51, .1, .1]])]
            recorded = []
            def capture(logits, target, **kwargs):
                recorded.append(target.clone())
                return original_bce(logits, target, **kwargs)
            with patch('training.loss._iou_with_target', side_effect=lambda boxes, target: torch.full((len(boxes),), iou)), \
                 patch('training.loss.F.binary_cross_entropy_with_logits', side_effect=capture):
                loss, _ = configured_detection_loss(outputs, targets, {"loss": {
                    "classification_mode": "bce", "classification_target": "binary", "assign_topk": 5}})
            label = recorded[0]
            self.assertEqual(int((label == 1).sum()), 5)
            self.assertTrue(((label == 0) | (label == 1)).all())
            loss.backward()
            self.assertTrue((scores.grad[label == 1] < 0).all())
            self.assertTrue(torch.isfinite(outputs[0][0].grad).all())

    def test_balanced_sampling(self):
        samples = [{"has_phone": i < 30, "id": i} for i in range(100)]
        selected = balanced_diagnostic_samples(samples, 20)
        self.assertEqual(sum(s["has_phone"] for s in selected), 10)
        self.assertEqual(len({s["id"] for s in selected}), 20)
        self.assertEqual(selected, balanced_diagnostic_samples(samples, 20))
        with self.assertRaises(ValueError):
            balanced_diagnostic_samples(samples, 100)

    def test_loss_gradients_and_hard_negatives(self):
        for mode in ("focal", "bce"):
            boxes = torch.zeros(2, 4, 8, 8, requires_grad=True)
            scores = torch.zeros(2, 1, 8, 8, requires_grad=True)
            loss, components = configured_detection_loss(
                [(boxes, scores)], [torch.tensor([[.5, .5, .1, .1]]), torch.empty(0, 4)],
                {"loss": {"classification_mode": mode}})
            loss.backward()
            self.assertTrue(torch.isfinite(loss))
            self.assertTrue(torch.isfinite(boxes.grad).all())
            self.assertTrue(torch.isfinite(scores.grad).all())
            self.assertGreater(float(components["box"]), 0)
        scores = torch.full((1, 1, 8, 8), -10.)
        scores[0, 0, 0, 0] = 5
        scores.requires_grad_()
        loss, _ = configured_detection_loss([(torch.zeros(1, 4, 8, 8), scores)],
                                            [torch.empty(0, 4)], {"loss": {"classification_mode": "bce"}})
        loss.backward()
        self.assertGreater(float(scores.grad[0, 0, 0, 0]), .05)

    def test_bn_check_preserves_buffers_and_modes_and_saves_overlay(self):
        model = ToyDetector().train()
        model.head.eval()
        loader = [(torch.rand(2, 3, 8, 8), [torch.empty(0, 4), torch.empty(0, 4)], ["a.jpg", "b.jpg"])]
        modes = [m.training for m in model.modules()]
        buffers = {name: value.clone() for name, value in model.named_buffers()}
        result = compare_batchnorm_modes(model, loader, torch.device("cpu"), {})
        self.assertTrue(all(torch.isfinite(torch.tensor(v)) for v in result.values()))
        self.assertEqual(modes, [m.training for m in model.modules()])
        for name, value in model.named_buffers():
            self.assertTrue(torch.equal(value, buffers[name]))
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[1]) as directory:
            save_prediction_overlays(model, loader, torch.device("cpu"), {}, Path(directory))
            self.assertEqual(len(list(Path(directory).glob("*.jpg"))), 2)
        self.assertEqual(modes, [m.training for m in model.modules()])


if __name__ == "__main__":
    unittest.main()
