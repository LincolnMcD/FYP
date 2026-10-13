"""Evaluate the final checkpoint on the held-out test split."""

from evaluation.validate import main


if __name__ == "__main__":
    main("test")
