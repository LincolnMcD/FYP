"""Shared configuration, path, and device helpers."""

from pathlib import Path

import torch
import yaml


PROJECT_ROOT = Path(__file__).resolve().parent


def load_config(path: str | Path | None = None) -> dict:
    """Load YAML configuration and resolve configured paths from the project root."""
    config_path = Path(path) if path else PROJECT_ROOT / "config" / "config.yaml"
    if not config_path.is_absolute():
        config_path = (Path.cwd() / config_path).resolve()
    if not config_path.is_file():
        raise FileNotFoundError(f"Configuration file not found: {config_path}")
    with config_path.open("r", encoding="utf-8") as stream:
        config = yaml.safe_load(stream) or {}

    config["_project_root"] = PROJECT_ROOT
    config["_config_path"] = config_path
    dataset = config.setdefault("dataset", {})
    dataset_root = Path(dataset.get("root", "../dataset"))
    dataset["root"] = (PROJECT_ROOT / dataset_root).resolve() if not dataset_root.is_absolute() else dataset_root
    for key in ("train_path", "val_path", "test_path"):
        value = dataset.get(key)
        if value:
            split_path = Path(value)
            dataset[key] = (PROJECT_ROOT / split_path).resolve() if not split_path.is_absolute() else split_path
    save_dir = Path(config.get("save_dir", "saved_models"))
    config["save_dir"] = (PROJECT_ROOT / save_dir).resolve() if not save_dir.is_absolute() else save_dir
    return config


def select_device(requested: str = "auto") -> torch.device:
    """Choose a usable torch device, falling back to CPU when needed."""
    if requested == "auto":
        return torch.device("cuda" if torch.cuda.is_available() else "cpu")
    device = torch.device(requested)
    if device.type == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA was requested but is not available in this PyTorch installation.")
    return device


def evaluation_config_path(config_path=None, checkpoint_path=None):
    """Prefer checkpoint-adjacent settings, then the configured output folder."""
    if config_path is not None:
        return config_path
    if checkpoint_path is not None:
        adjacent = Path(checkpoint_path).resolve().parent / "run_config.yaml"
        if adjacent.is_file():
            return adjacent
    current = load_config()
    saved = current["save_dir"] / "run_config.yaml"
    return saved if saved.is_file() else current["_config_path"]
