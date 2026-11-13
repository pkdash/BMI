"""Prove that setting a parameter through BMI matches editing the config.

Three runs of the same model, with identical forcing:

* **base**:   the original config;
* **config**: the parameter changed in the config (or wherever the model reads it);
* **bmi**:    the original config, then ``set`` right after ``initialize``. This is
  what a framework's "set parameters after initialize" feature does (ngen's
  ``model_params``).

``config`` vs ``bmi`` must be bit-identical for every output at every step:
anything the model derives from the parameter during ``initialize`` must also be
recomputed by its ``set_value``. ``base`` vs ``config`` shows whether the
parameter mattered at all in the test window; if it did not, the comparison
proves nothing and the result is ``unexercised`` (unless ``config`` and ``bmi``
differ anyway, which is ``differs``).

Used by the integration tests and by ``tools/check_equivalence.py``.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, ContextManager, Dict, Mapping, Optional, Sequence, Tuple

import numpy as np

from .model import Model

__all__ = ["run_steps", "compare_runs", "Equivalence", "check_equivalence"]

Opener = Callable[[], ContextManager[Model]]


def run_steps(model: Model, steps: int, forcing: Optional[Mapping[str, np.ndarray]] = None,
              outputs: Optional[Sequence[str]] = None) -> Dict[str, np.ndarray]:
    """Step ``model`` ``steps`` times and record every output after each step.

    ``forcing`` maps an input variable to one value per step, already in the
    model's units; each is set before the step's ``update``. Returns
    ``{output: array of shape (steps, length)}``.
    """
    outputs = list(outputs) if outputs is not None else model.output_names
    forcing = dict(forcing or {})
    for name, values in forcing.items():
        if len(values) < steps:
            raise ValueError(f"forcing {name!r} has {len(values)} values for {steps} steps")
    record: Dict[str, list] = {o: [] for o in outputs}
    for t in range(steps):
        for name, values in forcing.items():
            model.set(name, values[t])
        model.update()
        for o in outputs:
            record[o].append(np.asarray(model.get(o), dtype=float).copy())
    return {o: np.array(v) for o, v in record.items()}


def compare_runs(a: Mapping[str, np.ndarray], b: Mapping[str, np.ndarray]
                 ) -> Tuple[float, Optional[str], bool]:
    """``(largest relative difference, output where it occurs, bit-identical?)``.

    NaN equals NaN (both runs leaving an element unset is agreement).
    The relative difference is scaled by the largest magnitude of that output in
    either run; it is for reporting only, and "bit-identical" is the test.
    """
    worst, where, identical = 0.0, None, True
    for name in a:
        x, y = np.asarray(a[name], dtype=float), np.asarray(b[name], dtype=float)
        if x.shape != y.shape:
            return float("inf"), name, False
        same = (x == y) | (np.isnan(x) & np.isnan(y))
        if same.all():
            continue
        identical = False
        diff = np.abs(np.where(same, 0.0, x - y))
        diff = np.where(np.isnan(diff), np.inf, diff)
        both = np.abs(np.concatenate([x[np.isfinite(x)], y[np.isfinite(y)]]))
        scale = float(both.max()) if both.size else 0.0
        rel = float(np.max(diff) / scale) if scale > 0 else float("inf")
        if rel > worst or where is None:
            worst, where = rel, name
    return worst, where, identical


@dataclass
class Equivalence:
    name: str
    value: list
    effect: float                 # relative change base -> config
    effect_output: Optional[str]
    difference: float             # relative difference config vs bmi
    difference_output: Optional[str]
    status: str                   # "equivalent", "unexercised" or "differs"

    def as_dict(self) -> Dict:
        return dict(self.__dict__)


def check_equivalence(open_base: Opener, open_config: Opener, name: str, steps: int,
                      forcing: Optional[Mapping[str, np.ndarray]] = None,
                      value=None) -> Equivalence:
    """Compare a config edit of ``name`` with ``set(name, value)`` after initialize.

    ``open_base``/``open_config`` return a context manager yielding an
    initialized :class:`~bmi_setup.model.Model` for the original and edited
    configs (e.g. ``lambda: open_model("cfe", path)``). ``value`` defaults to
    what the model holds after reading the edited config, which keeps unit
    conversions done by the config reader out of the comparison.
    """
    with open_base() as m:
        base = run_steps(m, steps, forcing)
    with open_config() as m:
        if value is None:
            value = m.get(name)
        edited = run_steps(m, steps, forcing)
    with open_base() as m:
        m.set(name, value)
        via_bmi = run_steps(m, steps, forcing)
    effect, effect_out, unchanged = compare_runs(base, edited)
    diff, diff_out, identical = compare_runs(edited, via_bmi)
    # A config-vs-BMI difference is reported even when the config edit changed
    # nothing: BMI then did something the config does not.
    if not identical:
        status = "differs"
    elif unchanged:
        status = "unexercised"
    else:
        status = "equivalent"
    return Equivalence(name=name, value=np.atleast_1d(value).astype(float).tolist(),
                       effect=effect, effect_output=effect_out, difference=diff,
                       difference_output=diff_out, status=status)
