"""A pure-Python stand-in for a pymt_* wrapper, for tests that need no native model.

It mimics the behavior of the generated wrappers that ``Model`` relies on:
dtype names from ``get_var_type``, exact-length ``set_value`` with same_kind
casting, ``get_value`` without ``dest``, and lifecycle guards.
"""

import os

import numpy as np

LOG = []          # (event, instance id, cwd) across all instances


class FakeBmi:
    VARS = {          # name -> (dtype, length, initial)
        "scalar": ("float64", 1, 1.5),
        "layers": ("float32", 4, 0.3),
        "count": ("int32", 1, 2),
        "q_out": ("float64", 1, 0.0),
    }

    def __init__(self):
        self._vals = None
        self.finalized = 0

    def initialize(self, config):
        with open(config) as fh:                          # relative to the cwd, like models
            text = fh.read()
        if "fail" in text:
            raise RuntimeError("bad config")
        os.write(1, b"model chatter on stdout\n")      # native code writes to fd 1
        self._vals = {k: np.full(n, v, dtype=t) for k, (t, n, v) in self.VARS.items()}
        LOG.append(("initialize", id(self), os.getcwd()))

    def finalize(self):
        if self._vals is None:
            return
        self._vals = None
        self.finalized += 1
        LOG.append(("finalize", id(self), os.getcwd()))

    def _check(self, name):
        if name not in self.VARS:
            raise RuntimeError(f"unknown variable {name}")

    def get_var_type(self, name):
        self._check(name)
        return self.VARS[name][0]

    def get_var_itemsize(self, name):
        return np.dtype(self.get_var_type(name)).itemsize

    def get_var_nbytes(self, name):
        return self.get_var_itemsize(name) * self.VARS[name][1]

    def get_var_units(self, name):
        self._check(name)
        return "m"

    def get_input_var_names(self):
        return ("scalar",)

    def get_output_var_names(self):
        return ("q_out",)

    def get_value(self, name, dest=None):
        if self._vals is None:
            raise RuntimeError("not initialized")
        self._check(name)
        return self._vals[name].copy()

    def set_value(self, name, src):
        if self._vals is None:
            raise RuntimeError("not initialized")
        self._check(name)
        src = np.asarray(src)
        target = self._vals[name]
        if src.size != target.size:
            raise ValueError(f"expected {target.size} value(s), got {src.size}")
        if not np.can_cast(src.dtype, target.dtype, casting="same_kind"):
            raise TypeError(f"cannot cast {src.dtype} to {target.dtype}")
        target[:] = src.astype(target.dtype)

    def update(self):
        self._vals["q_out"] += self._vals["scalar"][0] * self._vals["layers"].sum()

    def update_until(self, t):
        self.update()

    def get_current_time(self):
        return 0.0

    def get_end_time(self):
        return 10.0

    def get_time_step(self):
        return 1.0
