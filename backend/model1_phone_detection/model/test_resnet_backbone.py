"""ResNet integration checks without downloading weights during unit tests."""

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import torch

from evaluation.validate import load_model
from model.phone_detector import build_model
from training.loss import configured_detection_loss
from training.scheduler import build_optimizer
from utils import evaluation_config_path


class ResNetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.old_threads = torch.get_num_threads()
        torch.set_num_threads(2)

    @classmethod
    def tearDownClass(cls):
        torch.set_num_threads(cls.old_threads)

    def config(self):
        return {"model": {"backbone": "resnet18", "pretrained": True, "width": .125},
                "learning_rate": .0003, "epochs": 10,
                "optimizer": {"warmup_epochs": 5, "backbone_lr_factor": .1},
                "loss": {"classification_mode": "bce", "classification_target": "binary", "negative_mining": "per_image"}}

    def test_shapes_normalization_freezing_and_gradients(self):
        model = build_model(self.config())
        images = torch.rand(2, 3, 64, 64)
        captured = []
        handle = model.backbone["stem"].register_forward_pre_hook(lambda module, args: captured.append(args[0].detach().clone()))
        model.set_backbone_trainable(False)
        model.train()
        self.assertFalse(model.backbone.training)
        outputs = model(images)
        handle.remove()
        self.assertTrue(torch.allclose(captured[0], (images-model.input_mean)/model.input_std))
        self.assertEqual([pair[0].shape[-2:] for pair in outputs], [(8, 8), (4, 4), (2, 2)])
        targets = [torch.tensor([[.31,.31,.1,.1],[.51,.51,.2,.2],[.61,.61,.5,.5]]), torch.empty(0,4)]
        loss, _ = configured_detection_loss(outputs, targets, self.config())
        loss.backward()
        self.assertTrue(all(p.grad is None for p in model.backbone.parameters()))
        self.assertTrue(any(p.grad is not None and p.grad.abs().sum() > 0 for p in model.head.parameters()))
        model.zero_grad(set_to_none=True)
        model.set_backbone_trainable(True)
        self.assertTrue(all(not m.training for m in model.backbone.modules() if isinstance(m, torch.nn.BatchNorm2d)))
        loss, _ = configured_detection_loss(model(images), targets, self.config())
        loss.backward()
        self.assertGreater(float(model.backbone["stem"][0].weight.grad.abs().sum()), 0.)
        self.assertTrue(all(torch.isfinite(p.grad).all() for p in model.parameters() if p.grad is not None))

    def test_checkpoint_roundtrip_without_pretrained_download_and_legacy(self):
        config = self.config()
        model = build_model(config).eval()
        images = torch.rand(1, 3, 64, 64)
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[1]) as directory:
            path = Path(directory)/"best.pt"
            torch.save({"format_version": 2, "model": model.state_dict(), "model_config": config["model"]}, path)
            with patch('torchvision.models.ResNet18_Weights.get_state_dict', side_effect=AssertionError("unexpected download")):
                loaded = load_model(path, {"model": {"backbone": "custom"}}, torch.device("cpu")).eval()
            with torch.no_grad():
                for expected, actual in zip(model(images), loaded(images)):
                    self.assertTrue(torch.equal(expected[0], actual[0]))
                    self.assertTrue(torch.equal(expected[1], actual[1]))
            legacy = build_model({"model": {"width": .125}})
            torch.save({"format_version": 2, "model": legacy.state_dict()}, path)
            self.assertEqual(load_model(path, config, torch.device("cpu")).backbone_name, "custom")
            adjacent = Path(directory)/"run_config.yaml"
            adjacent.write_text("model: {}")
            self.assertEqual(evaluation_config_path(checkpoint_path=path), adjacent)

    def test_backbone_has_lower_lr_and_remains_in_optimizer_when_frozen(self):
        model = build_model(self.config())
        model.set_backbone_trainable(False)
        optimizer, scheduler = build_optimizer(model, self.config())
        self.assertAlmostEqual(optimizer.param_groups[1]["lr"], optimizer.param_groups[0]["lr"]*.1)
        registered = {id(p) for group in optimizer.param_groups for p in group["params"]}
        self.assertTrue(all(id(p) in registered for p in model.backbone.parameters()))


if __name__ == "__main__":
    unittest.main()
