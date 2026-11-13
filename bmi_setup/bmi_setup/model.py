"""A safe handle on one pymt_* wrapper instance.

    with open_model("cfe", "cat-11223_bmi_config_cfe_pass.txt", workdir=".") as m:
        m.get("b")              # np.ndarray; dtype and length come from the library
        m.set("satdk", 2e-5)    # scalar broadcast to the variable's length
        m.update()

What this adds over calling the wrapper directly:

* **Guaranteed finalize.** ``open_model`` is a context manager, and a
  ``weakref.finalize`` safety net finalizes a ``Model`` that is garbage-collected
  while still initialized. The Fortran wrappers keep model handles in a fixed
  table of 2048 slots that only ``finalize`` releases, so instances dropped
  without it eventually make every new instance fail. ``Model`` creates the
  wrapper only when it is first needed, so a ``Model`` that is never
  initialized takes no slot. A failed native ``initialize`` keeps its slot
  (finalizing an uninitialized Fortran model is unsafe), so do not retry
  failures in an unbounded loop with new ``Model`` objects.
* **Working directory.** Models resolve the relative paths in their config at
  ``initialize``. ``initialize`` runs inside a temporary ``chdir`` to
  ``workdir`` and the previous directory is restored afterwards. ``chdir`` is
  process-wide, so a ``Model`` must not be initialized from several threads at
  once; use processes for parallel runs.
* **Model chatter** printed by native code during ``initialize`` and
  ``finalize`` goes to stderr, so it cannot corrupt a caller's stdout.
* **Deliberate broadcast.** The wrappers require ``set_value`` to receive
  exactly the variable's length. ``Model.set`` expands a scalar to that length
  (e.g. one value for all four Noah soil layers). A sequence of any other length
  is rejected before the native call.
* **Errors name the model and variable.**
* **Catalog check.** When the model has a parameter catalog, every
  BMI-settable entry is checked against the library at ``initialize``
  (see :mod:`bmi_setup.catalog`).
"""

from __future__ import annotations

import contextlib
import ctypes
import os
import sys
import weakref
from pathlib import Path
from typing import Dict, Iterator, List, Optional, Union

import numpy as np

from .catalog import Catalog, Parameter, load_catalog
from .models import get_spec, load_class

__all__ = ["Model", "open_model", "chatter_to_stderr"]

PathLike = Union[str, "os.PathLike[str]"]


def _flush_c_streams() -> None:
    """Flush libc stdio, which buffers when stdout is not a terminal."""
    try:
        ctypes.CDLL(None).fflush(None)
    except Exception:                                   # noqa: BLE001 - best effort
        pass


@contextlib.contextmanager
def chatter_to_stderr() -> Iterator[None]:
    """Send anything written to file descriptor 1 to stderr instead.

    Native models print with C stdio or Fortran ``write(*,*)``, which bypass
    ``sys.stdout``, so the redirect is done on the file descriptor. If fd 1 or
    2 cannot be duplicated (some embedded interpreters), it does nothing.
    """
    try:
        sys.stdout.flush()
        saved = os.dup(1)
    except (OSError, ValueError):
        yield
        return
    try:
        os.dup2(2, 1)
        yield
    finally:
        try:
            sys.stdout.flush()
        except ValueError:
            pass
        _flush_c_streams()
        os.dup2(saved, 1)
        os.close(saved)


@contextlib.contextmanager
def _chdir(path: Optional[PathLike]) -> Iterator[None]:
    if path is None:
        yield
        return
    previous = os.getcwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(previous)


def _with_context(err: BaseException, message: str) -> BaseException:
    """``err``'s type with ``message``, or ``RuntimeError`` if that type can't take one."""
    try:
        return type(err)(message)
    except Exception:                                   # noqa: BLE001
        return RuntimeError(message)


def _finalize_quietly(bmi) -> None:
    """Safety-net finalize: runs at garbage collection, so it must not raise."""
    try:
        with chatter_to_stderr():
            bmi.finalize()
    except Exception:                                   # noqa: BLE001
        pass


class Model:
    """One model instance: a pymt_* wrapper plus safe lifecycle and access.

    ``model`` is a key from :data:`bmi_setup.models.MODELS` (``"cfe"``,
    ``"noah"``, ...) or a wrapper class. ``catalog`` overrides the packaged
    catalog for a key (pass ``False`` to use none).

    The raw wrapper instance is available as :attr:`bmi` for anything this
    class does not cover.
    """

    def __init__(self, model: Union[str, type], catalog: Union[Catalog, None, bool] = None):
        if isinstance(model, str):
            self.key: Optional[str] = model
            cls = load_class(model)
            spec = get_spec(model)
            # True insists on the packaged catalog (KeyError if the model has none).
            if catalog is True or (catalog is None and spec.catalog):
                catalog = load_catalog(model)
        else:
            if catalog is True:
                raise TypeError("catalog=True needs a model key; pass a Catalog for a wrapper class")
            self.key, cls = None, model
        if catalog is not None and not isinstance(catalog, (Catalog, bool)):
            raise TypeError(f"catalog must be a Catalog, None or a bool, not {type(catalog).__name__}")
        self.catalog: Optional[Catalog] = catalog if isinstance(catalog, Catalog) else None
        self._cls = cls
        self._bmi = None
        self.config: Optional[Path] = None
        self.workdir: Optional[Path] = None
        self._initialized = False
        self._finalizer: Optional[weakref.finalize] = None

    @property
    def bmi(self):
        """The wrapper instance, created on first use.

        Creation is delayed because the Fortran wrappers take one of their 2048
        model slots when the instance is created, and only the model's
        ``finalize`` gives it back. That ``finalize`` must not run on a model
        that was never initialized, so a slot taken by a ``Model`` that is never
        initialized could never be released.
        """
        if self._bmi is None:
            self._bmi = self._cls()
        return self._bmi

    @property
    def name(self) -> str:
        return self.key or self._cls.__name__

    def __repr__(self) -> str:
        state = "initialized" if self._initialized else "not initialized"
        return f"<Model {self.name} {state} config={str(self.config) if self.config else None}>"

    # ------------------------------------------------------------ lifecycle
    @property
    def initialized(self) -> bool:
        return self._initialized

    def initialize(self, config: PathLike, workdir: Optional[PathLike] = None,
                   check_catalog: bool = True) -> "Model":
        """Initialize from ``config``, with ``workdir`` as the current directory.

        With ``workdir`` given, ``config`` is passed to the model as given, so
        a relative ``config`` is relative to ``workdir``. Without it, a relative
        ``config`` is relative to the current directory, ``workdir`` becomes the
        directory containing it, and the model gets the absolute config path.
        On success the catalog (if any) is checked against the library; a
        mismatch finalizes the model and raises
        :class:`bmi_setup.catalog.CatalogMismatch`.

        If the native ``initialize`` fails, a Fortran wrapper keeps its model
        slot (see :attr:`bmi`); retrying ``initialize`` on this ``Model`` reuses it.
        """
        if self._initialized:
            raise RuntimeError(f"{self.name}: already initialized")
        if workdir is None:
            resolved = Path(config).resolve()
            workdir, config = resolved.parent, resolved
        else:
            workdir = Path(workdir).resolve()
            resolved = Path(config) if Path(config).is_absolute() else workdir / config
        if not resolved.is_file():
            raise FileNotFoundError(f"{self.name}: config file not found: {resolved}")
        bmi = self.bmi
        with _chdir(workdir), chatter_to_stderr():
            try:
                bmi.initialize(str(config))
            except Exception as err:
                raise _with_context(err, f"{self.name}: initialize({str(config)!r}) in "
                                         f"{workdir} failed: {err}") from err
        self._initialized = True
        self.config, self.workdir = resolved, workdir
        self._finalizer = weakref.finalize(self, _finalize_quietly, bmi)
        if check_catalog and self.catalog is not None:
            try:
                self.catalog.check(self)
            except Exception:
                self.finalize()
                raise
        return self

    def finalize(self) -> None:
        """Release the model. Safe to call more than once."""
        if not self._initialized:
            return
        self._initialized = False
        if self._finalizer is not None:
            self._finalizer.detach()
            self._finalizer = None
        with chatter_to_stderr():
            self.bmi.finalize()

    def __enter__(self) -> "Model":
        return self

    def __exit__(self, *exc) -> None:
        self.finalize()

    # ------------------------------------------------------------ variables
    def _require_initialized(self, what: str) -> None:
        if not self._initialized:
            raise RuntimeError(f"{self.name}: {what} needs an initialized model")

    def var_dtype(self, name: str) -> np.dtype:
        return np.dtype(self._call("get_var_type", name))

    def var_length(self, name: str) -> int:
        """Number of elements, ``get_var_nbytes // get_var_itemsize``."""
        itemsize = self._call("get_var_itemsize", name)
        nbytes = self._call("get_var_nbytes", name)
        if itemsize <= 0 or nbytes % itemsize:
            raise RuntimeError(f"{self.name}: {name!r} reports {nbytes} bytes with "
                               f"item size {itemsize}")
        return nbytes // itemsize

    def var_units(self, name: str) -> str:
        return self._call("get_var_units", name)

    def is_var(self, name: str) -> bool:
        """True when the library knows ``name`` (whether or not it is advertised)."""
        try:
            self.bmi.get_var_type(name)
            return True
        except Exception:                               # noqa: BLE001
            return False

    @property
    def input_names(self) -> List[str]:
        return list(self.bmi.get_input_var_names())

    @property
    def output_names(self) -> List[str]:
        return list(self.bmi.get_output_var_names())

    def _call(self, method: str, name: str, *args):
        try:
            return getattr(self.bmi, method)(name, *args)
        except Exception as err:
            raise _with_context(err, f"{self.name}: {method}({name!r}) failed: {err}") from err

    def get(self, name: str) -> np.ndarray:
        """A new 1-D array with the current value of ``name``.

        A multi-element variable is copied from ``get_value_ptr`` when the
        wrapper supports it, because native CFE ``get_value`` copies only
        element 0 (documented in ``common/README.md``). Where the pointer is
        not available (Noah-OWP, Sac-SMA), ``get_value`` is used.
        """
        self._require_initialized(f"get({name!r})")
        if hasattr(self.bmi, "get_value_ptr") and self.var_length(name) > 1:
            try:
                return np.array(self.bmi.get_value_ptr(name), copy=True).ravel()
            except Exception:                           # noqa: BLE001 - fall back below
                pass
        return self._call("get_value", name)

    def set(self, name: str, value) -> None:
        """Set ``name`` to ``value``.

        A scalar is broadcast to the variable's length. A sequence must have
        exactly that length. Values are converted to the variable's dtype by the
        wrapper, which allows only safe conversions (e.g. int to float, but not
        float to int).
        """
        self._require_initialized(f"set({name!r})")
        length = self.var_length(name)
        array = np.asarray(value)
        if array.dtype == object:
            raise TypeError(f"{self.name}: {name!r}: cannot set a value of type "
                            f"{type(value).__name__}")
        if array.ndim == 0:
            array = np.full(length, array, dtype=array.dtype)
        else:
            array = array.ravel()
            if array.size != length:
                raise ValueError(f"{self.name}: {name!r} has {length} element(s); got "
                                 f"{array.size}. Pass a scalar to set every element.")
        self._call("set_value", name, array)

    # ------------------------------------------------------------ time
    def update(self) -> None:
        self._require_initialized("update()")
        self.bmi.update()

    def update_until(self, time: float) -> None:
        self._require_initialized("update_until()")
        self.bmi.update_until(time)

    @property
    def current_time(self) -> float:
        return self.bmi.get_current_time()

    @property
    def end_time(self) -> float:
        return self.bmi.get_end_time()

    @property
    def time_step(self) -> float:
        return self.bmi.get_time_step()

    # ------------------------------------------------------------ parameters
    def parameters(self) -> Dict[str, Dict]:
        """Catalog entries, with ``value`` read live for the BMI-settable ones."""
        if self.catalog is None:
            return {}
        out = {}
        for p in self.catalog:
            row = p.as_dict()
            if p.bmi and self._initialized:
                row["value"] = self.get(p.name)
            out[p.name] = row
        return out

    def parameter(self, name: str) -> Parameter:
        if self.catalog is None:
            raise KeyError(f"{self.name} has no parameter catalog")
        return self.catalog[name]


def open_model(model: Union[str, type], config: PathLike, workdir: Optional[PathLike] = None,
               catalog: Union[Catalog, None, bool] = None, check_catalog: bool = True) -> Model:
    """Create and initialize a :class:`Model`; use it as a context manager.

    ``with open_model(...) as m:`` finalizes ``m`` on exit, even after an error.
    """
    m = Model(model, catalog=catalog)
    m.initialize(config, workdir, check_catalog=check_catalog)
    return m
