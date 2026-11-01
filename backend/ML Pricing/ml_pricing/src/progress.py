"""Live boosting progress and durable, per-iteration regression metrics."""
import time
import pandas as pd


class TrainingProgress:
    def __init__(self, total, every=1):
        self.total, self.every = total, every
        self.started = time.perf_counter()
        self.last = None
        print(" Iteration | Train RMSE | Valid RMSE | Train MAE | Valid MAE | Train R2 | Valid R2 | Seconds")
        print("-" * 100)

    def after_iteration(self, info):
        self.last = info
        if info.iteration == 1 or info.iteration % self.every == 0 or info.iteration == self.total:
            self.display(info)
        return True

    def display(self, info):
        tr, va = info.metrics["learn"], info.metrics["validation"]
        print(f"{info.iteration:6d}/{self.total:<6d} | {tr['RMSE'][-1]:10.6f} | {va['RMSE'][-1]:10.6f} | "
              f"{tr['MAE'][-1]:9.6f} | {va['MAE'][-1]:9.6f} | "
              f"{tr['R2'][-1]:8.4f} | {va['R2'][-1]:8.4f} | {time.perf_counter()-self.started:7.1f}", flush=True)


def save_learning_history(model, outdir, key):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    history = model.get_evals_result()
    columns = {f"{split}_{metric.lower()}": values
               for split, metrics in history.items() for metric, values in metrics.items()}
    frame = pd.DataFrame(columns)
    frame.insert(0, "iteration", range(1, len(frame) + 1))
    frame.to_csv(outdir / f"{key}_learning_history.csv", index=False)
    fig, axes = plt.subplots(1, 3, figsize=(15, 4))
    for ax, metric in zip(axes, ("RMSE", "MAE", "R2")):
        for split, label in (("learn", "Train"), ("validation", "Validation")):
            ax.plot(frame.iteration, frame[f"{split}_{metric.lower()}"], label=label)
        ax.axvline(model.best_iteration_ + 1, color="gray", linestyle="--", label="Best iteration")
        ax.set(xlabel="Boosting iteration", ylabel=metric, title=f"Retention ratio {metric}")
        ax.legend()
        ax.grid(alpha=.2)
    fig.suptitle(key)
    fig.tight_layout()
    figures = outdir / "figures"
    figures.mkdir(exist_ok=True)
    fig.savefig(figures / f"{key}_learning_curves.png", dpi=140)
    plt.close(fig)
