"""Desktop image tester for the fine-tuned phone detector."""

from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from PIL import Image, ImageOps, ImageTk
import torch
import yaml

from predict import load_model, predict


PROJECT = Path(__file__).resolve().parent
COLORS = ("#5ee8aa", "#ffd170")


def default_weights():
    config = yaml.safe_load((PROJECT / "train.yaml").read_text(encoding="utf-8"))
    configured = PROJECT / config["output"] / "best.pt"
    if configured.is_file():
        return configured
    for run in ("phone26n_dynamic", "phone26n"):
        previous = PROJECT / "runs" / run / "best.pt"
        if previous.is_file():
            return previous
    return configured


class Tester:
    def __init__(self, window):
        self.window = window
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.weights = default_weights()
        self.loaded = None
        self.image_path = None
        self.image = None
        self.preview = None
        self.parts = []

        window.title("Phone Part Detector")
        window.geometry("850x640")
        window.minsize(560, 420)
        panel = ttk.Frame(window, padding=14)
        panel.pack(fill="both", expand=True)
        toolbar = ttk.Frame(panel)
        toolbar.pack(fill="x")
        ttk.Button(toolbar, text="Open image", command=self.choose_image).pack(side="left")
        ttk.Button(toolbar, text="Choose checkpoint", command=self.choose_weights).pack(side="left", padx=8)
        self.result = ttk.Label(panel, text="Open an image to run detection.")
        self.result.pack(fill="x", pady=(12, 5))
        self.details = ttk.Label(panel, text=self.weights.parent.name + "/" + self.weights.name)
        self.details.pack(fill="x", pady=(0, 10))
        self.canvas = tk.Canvas(panel, background="#171c25", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)
        self.canvas.bind("<Configure>", self.draw)

    def choose_weights(self):
        filename = filedialog.askopenfilename(
            parent=self.window, title="Choose a fine-tuned checkpoint",
            initialdir=self.weights.parent if self.weights.parent.is_dir() else PROJECT,
            filetypes=[("PyTorch checkpoint", "*.pt")])
        if filename:
            self.weights = Path(filename)
            self.details.configure(text=str(self.weights))
            if self.image_path is not None:
                self.detect(self.image_path)

    def choose_image(self):
        filename = filedialog.askopenfilename(
            parent=self.window, title="Open an image",
            filetypes=[("Images", "*.jpg *.jpeg *.png *.webp *.bmp"), ("All files", "*.*")])
        if filename:
            self.detect(Path(filename))

    def detect(self, path):
        try:
            revision = (self.weights, self.weights.stat().st_mtime_ns)
            if self.loaded != revision:
                self.model, self.checkpoint = load_model(self.weights, self.device)
                self.loaded = revision
            ck = self.checkpoint
            result = predict(self.model, path, ck["size"], ck["names"], ck["confidence"], self.device)
            with Image.open(path) as source:
                image = ImageOps.exif_transpose(source).convert("RGB")
        except Exception as error:
            messagebox.showerror("Detection failed", str(error), parent=self.window)
            return
        self.image_path, self.image, self.parts = path, image, result["parts"]
        count = len(self.parts)
        self.result.configure(text=f"Phone detected · {count} box{'es' if count != 1 else ''}"
                              if result["phone"] else "No phone detected")
        self.details.configure(text=f"{self.weights.parent.name}/{self.weights.name}"
                               f"  |  Epoch {ck['epoch']}  |  Confidence ≥ {ck['confidence']:.6g}"
                               f"  |  {self.device.type.upper()}")
        self.draw()

    def draw(self, event=None):
        if self.image is None:
            return
        width, height = self.canvas.winfo_width(), self.canvas.winfo_height()
        if min(width, height) < 2:
            return
        preview = ImageOps.contain(self.image, (width, height), Image.Resampling.BILINEAR)
        self.preview = ImageTk.PhotoImage(preview)
        left, top = (width - preview.width) / 2, (height - preview.height) / 2
        sx, sy = preview.width / self.image.width, preview.height / self.image.height
        self.canvas.delete("all")
        self.canvas.create_image(left, top, image=self.preview, anchor="nw")
        for part, color in zip(self.parts, COLORS):
            x1, y1, x2, y2 = part["xyxy"]
            x1, x2 = left + sx * x1, left + sx * x2
            y1, y2 = top + sy * y1, top + sy * y2
            self.canvas.create_rectangle(x1, y1, x2, y2, outline=color, width=2)
            name = part["class"].removeprefix("mobile-phone-").replace("-", " ")
            label = self.canvas.create_text(x1 + 3, max(2, y1 - 20),
                                            text=f"{name}  {part['confidence']:.1%}",
                                            fill="#161b22", anchor="nw", font=("Segoe UI", 10, "bold"))
            background = self.canvas.create_rectangle(self.canvas.bbox(label), fill=color, outline=color)
            self.canvas.tag_lower(background, label)


def main():
    window = tk.Tk()
    Tester(window)
    window.mainloop()


if __name__ == "__main__":
    main()
