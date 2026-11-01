"""Local desktop tester for saved, custom-trained phone price models.

Run: python ui.py
Or:  python ui.py --model path/to/model.json
"""
import argparse
import json
from pathlib import Path
import numpy as np
import pandas as pd
from ml_pricing.src.config import ROOT
from ml_pricing.src.predict import validate_request
from ml_pricing.src.preprocessing import prepare_features
from ml_pricing.src.scratch import ScratchBoostRegressor


def discover_models(directory=ROOT / 'scratch_runs'):
    return sorted(Path(directory).glob('*/model.json'), key=lambda p: p.stat().st_mtime_ns, reverse=True)


class ModelTester:
    """Prediction backend, usable without opening a window or retraining."""
    def __init__(self, path):
        self.path = Path(path).resolve()
        self.model = ScratchBoostRegressor.load(self.path)
        self.configuration = 'with_model' if 'model' in self.model.features else 'without_model'

    def categories(self, column):
        if hasattr(self.model, 'specs'):
            stats = self.model.category_maps.get(json.dumps([column]))
            if not stats:
                return []
            return sorted(json.loads(key)[0] for key in stats['count'])
        return sorted(self.model.category_maps.get(column, {}))

    def predict(self, values, actual_price=None):
        request = dict(values)
        validate_request(request)
        if actual_price is not None:
            actual_price = float(actual_price)
            if not np.isfinite(actual_price) or actual_price < 0:
                raise ValueError('Actual selling price must be a finite, nonnegative number')
        X = prepare_features(pd.DataFrame([request]), self.configuration)
        raw_ratio = float(self.model.predict(X)[0])
        if not np.isfinite(raw_ratio):
            raise ValueError('Model returned a non-finite prediction')
        ratio = float(np.clip(raw_ratio, 0, .9999))
        price = round(request['msrp'] * ratio, 2)
        result = {'retention_ratio': ratio, 'raw_retention_ratio': raw_ratio,
                  'estimated_price_myr': price, 'depreciation_percent': (1-ratio)*100}
        if actual_price is not None:
            result.update(actual_price_myr=actual_price, absolute_error_myr=abs(price-actual_price),
                          signed_error_myr=price-actual_price)
        return result


class TesterWindow:
    def __init__(self, window, initial_model=None):
        import tkinter as tk
        from tkinter import ttk, filedialog, messagebox
        self.tk, self.ttk = tk, ttk
        self.filedialog, self.messagebox = filedialog, messagebox
        self.window, self.tester = window, None
        window.title('Phone price · Custom model tester')
        window.geometry('1080x790'); window.minsize(950, 740)
        window.configure(bg='#f3f6fa')
        style = ttk.Style(window); style.theme_use('clam')
        style.configure('.', font=('Segoe UI', 10))
        style.configure('TFrame', background='#f3f6fa')
        style.configure('TLabel', background='#f3f6fa', foreground='#1b3045')
        style.configure('Title.TLabel', font=('Segoe UI', 23, 'bold'))
        style.configure('Heading.TLabel', font=('Segoe UI', 13, 'bold'))
        style.configure('Muted.TLabel', foreground='#576a7d')
        style.configure('Price.TLabel', font=('Segoe UI', 32, 'bold'), foreground='#087f76')
        style.configure('Predict.TButton', font=('Segoe UI', 12, 'bold'), padding=12)
        style.configure('TEntry', padding=6)
        style.configure('TCombobox', padding=5)
        outer = ttk.Frame(window, padding=26); outer.pack(fill='both', expand=True)
        outer.columnconfigure(0, weight=1)
        ttk.Label(outer, text='Phone price tester', style='Title.TLabel').grid(row=0, column=0, sticky='w')
        ttk.Label(outer, text='Load a saved custom model and try a phone. Predictions do not retrain it.', style='Muted.TLabel').grid(row=1, column=0, sticky='w', pady=(3, 18))

        selector = ttk.Frame(outer); selector.grid(row=2, column=0, sticky='ew')
        selector.columnconfigure(0, weight=1)
        self.paths = discover_models()
        self.run = tk.StringVar()
        self.run_combo = ttk.Combobox(selector, textvariable=self.run, state='readonly',
                                      values=[p.parent.name for p in self.paths])
        self.run_combo.grid(row=0, column=0, sticky='ew', padx=(0, 10))
        self.run_combo.bind('<<ComboboxSelected>>', lambda event: self.load_model(self.paths[self.run_combo.current()]))
        ttk.Button(selector, text='Browse model.json…', command=self.browse).grid(row=0, column=1)
        self.model_info = tk.StringVar(value='No model loaded. Browse to a saved custom model.json file.')
        ttk.Label(outer, textvariable=self.model_info, style='Muted.TLabel', wraplength=990).grid(row=3, column=0, sticky='w', pady=(8, 18))

        content = ttk.Frame(outer); content.grid(row=4, column=0, sticky='nsew')
        outer.rowconfigure(4, weight=1)
        content.columnconfigure(0, weight=3); content.columnconfigure(1, weight=2)
        form = ttk.Frame(content); form.grid(row=0, column=0, sticky='new', padx=(0, 30))
        form.columnconfigure(0, weight=1); form.columnconfigure(1, weight=1)
        ttk.Label(form, text='Phone details', style='Heading.TLabel').grid(row=0, column=0, columnspan=2, sticky='w', pady=(0, 12))
        fields = [
            ('brand', 'Brand', 'Apple'), ('model', 'Phone model', 'iPhone 13'),
            ('deviceAge', 'Age (whole years, 0–10)', '3'), ('msrp', 'Original MSRP (RM)', '3899'),
            ('ramCapacity', 'RAM (GB)', '4'), ('storage', 'Storage (GB)', '128'),
            ('internalPerfromanceOverallMark', 'Performance score (0–100)', '90'),
            ('hasScreenDamage', 'Screen damage? (0 = no, 1 = yes)', '0'),
            ('screenDmgScore', 'Screen damage score (≥ 0)', '0'),
            ('totalDmgScore', 'Total damage score (≥ 0)', '2')]
        self.inputs, self.widgets = {}, {}
        for index, (key, label, default) in enumerate(fields):
            row, col = 1 + (index//2)*2, index%2
            ttk.Label(form, text=label).grid(row=row, column=col, sticky='w', padx=(0, 12), pady=(0, 4))
            variable = tk.StringVar(value=default); self.inputs[key] = variable
            if key in ('brand', 'model', 'hasScreenDamage'):
                widget = ttk.Combobox(form, textvariable=variable, width=23,
                                      values=('0', '1') if key == 'hasScreenDamage' else (),
                                      state='readonly' if key == 'hasScreenDamage' else 'normal')
            else:
                widget = ttk.Entry(form, textvariable=variable, width=25)
            widget.grid(row=row+1, column=col, sticky='ew', padx=(0, 12), pady=(0, 12))
            self.widgets[key] = widget
            variable.trace_add('write', self.clear_prediction)

        ttk.Label(form, text='Actual selling price (RM, optional)').grid(row=11, column=0, columnspan=2, sticky='w', pady=(2, 4))
        self.actual = tk.StringVar(); self.actual.trace_add('write', self.clear_prediction)
        ttk.Entry(form, textvariable=self.actual).grid(row=12, column=0, columnspan=2, sticky='ew', padx=(0, 12))
        self.predict_button = ttk.Button(form, text='Predict retention & price', command=self.predict, style='Predict.TButton', state='disabled')
        self.predict_button.grid(row=13, column=0, columnspan=2, sticky='ew', padx=(0, 12), pady=(18, 0))

        results = ttk.Frame(content, padding=(12, 0, 0, 0)); results.grid(row=0, column=1, sticky='new')
        ttk.Label(results, text='Estimated selling price', style='Heading.TLabel').pack(anchor='w')
        self.price = tk.StringVar(value='RM —')
        ttk.Label(results, textvariable=self.price, style='Price.TLabel').pack(anchor='w', pady=(12, 4))
        self.retention = tk.StringVar(value='Retention: —')
        self.depreciation = tk.StringVar(value='Depreciation: —')
        self.comparison = tk.StringVar(value='Enter an actual price to compare a prediction.')
        self.exposure = tk.StringVar(value='')
        ttk.Label(results, textvariable=self.retention, font=('Segoe UI', 14)).pack(anchor='w', pady=5)
        ttk.Label(results, textvariable=self.depreciation).pack(anchor='w', pady=5)
        ttk.Separator(results).pack(fill='x', pady=20)
        ttk.Label(results, textvariable=self.comparison, wraplength=345).pack(anchor='w')
        ttk.Label(results, textvariable=self.exposure, style='Muted.TLabel', wraplength=345).pack(anchor='w', pady=(20, 0))
        ttk.Label(results, text='Estimate = MSRP × predicted retention.\n\nThis model was trained on synthetic data; these estimates are for testing.',
                  wraplength=345, style='Muted.TLabel').pack(anchor='w', pady=(20, 0))
        self.path_label = tk.StringVar()
        ttk.Label(outer, textvariable=self.path_label, style='Muted.TLabel', wraplength=990).grid(row=5, column=0, sticky='w', pady=(18, 0))
        window.bind('<Return>', lambda event: self.predict())
        if initial_model:
            self.load_model(initial_model)
        elif self.paths:
            self.load_model(self.paths[0])

    def clear_prediction(self, *_):
        if hasattr(self, 'price'):
            self.price.set('RM —'); self.retention.set('Retention: —'); self.depreciation.set('Depreciation: —')
            self.comparison.set('Enter an actual price to compare a prediction.'); self.exposure.set('')

    def browse(self):
        path = self.filedialog.askopenfilename(title='Load custom trained model', filetypes=[('Custom model JSON', '*.json')],
                                               initialdir=str(ROOT/'scratch_runs'))
        if path:
            self.load_model(path)

    def load_model(self, path):
        try:
            candidate = ModelTester(path)
            # Reject incomplete/corrupt models before enabling prediction.
            if not candidate.model.trees:
                raise ValueError('This file has no saved trees')
        except Exception as exc:
            self.messagebox.showerror('Could not load model', str(exc))
            # Keep the displayed selection consistent with the model still loaded.
            if self.tester:
                self.run.set(self.tester.path.parent.name)
            return
        self.tester = candidate
        self.run.set(candidate.path.parent.name)
        self.clear_prediction()
        model = candidate.model
        mode = model.params.get('boosting', 'plain')
        self.model_info.set(f'{candidate.configuration}  •  {mode} boosting  •  {len(model.trees)} saved trees  •  '
                            f'Best validation iteration: {model.best_iteration}\n'
                            'Each run stores its best validation snapshot. Latest saved run is selected on startup.')
        self.path_label.set(f'Loaded: {candidate.path}')
        for column in ('brand', 'model'):
            self.widgets[column].configure(values=candidate.categories(column))
        self.predict_button.configure(state='normal')

    def predict(self):
        if self.tester is None:
            return
        try:
            result = self.tester.predict({key: value.get() for key, value in self.inputs.items()},
                                         self.actual.get().strip() or None)
        except Exception as exc:
            self.clear_prediction()
            self.messagebox.showerror('Check phone details', str(exc))
            return
        self.price.set(f"RM {result['estimated_price_myr']:,.2f}")
        self.retention.set(f"Retention: {result['retention_ratio']:.1%}")
        self.depreciation.set(f"Depreciation: {result['depreciation_percent']:.1f}%")
        if 'absolute_error_myr' in result:
            self.comparison.set(f"Actual price: RM {result['actual_price_myr']:,.2f}\n"
                                f"Absolute error: RM {result['absolute_error_myr']:,.2f}\n"
                                f"Prediction minus actual: RM {result['signed_error_myr']:+,.2f}")
        else:
            self.comparison.set('Enter an actual price to compare a prediction.')
        model_name = self.inputs['model'].get().strip().casefold()
        known = self.tester.categories('model')
        text = ('Phone model was seen in training.' if model_name in known else 'Phone model was not seen in training; categorical fallback is used.') if known else 'This predictor does not use phone model names.'
        if result['raw_retention_ratio'] != result['retention_ratio']:
            text += '\nRetention was clipped to the supported range.'
        self.exposure.set(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, help='Saved custom model.json; defaults to latest saved run')
    args = parser.parse_args()
    import tkinter as tk
    window = tk.Tk()
    TesterWindow(window, args.model)
    window.mainloop()


if __name__ == '__main__':
    main()
