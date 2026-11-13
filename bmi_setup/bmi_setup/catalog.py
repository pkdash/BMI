"""Parameter catalogs: which parameters a model has and how each may be changed.

The pymt_* wrappers carry no parameter metadata, and most models do not list
their calibration parameters among their BMI inputs. Each supported model
therefore has a catalog file (``bmi_setup/catalogs/<model>.json``) that is
drafted by ``tools/probe_parameters.py``, reviewed by a person, and checked in.
Every time a model with a catalog is initialized, the catalog is checked against
the compiled library (:meth:`Catalog.check`), so a library that has changed
cannot be used with a stale catalog.

Entry fields:

``dtype``, ``length``
    As the library reports them (``get_var_type``; ``get_var_nbytes //
    get_var_itemsize``). ``length`` may be the name of a config key when it
    depends on the config (Noah's soil layers: ``"nsoil"``), or ``null`` for a
    config-only list of free length.
``units``
    From ``get_var_units`` (BMI entries), or the config's own unit.
``config_key``
    The key that sets the same value in the model's own init config, for the
    codec named by the model's spec, or ``null`` when the parameter can only
    be reached through BMI.
``source``
    Optional: where the value comes from when it is not ``config_key``
    (e.g. Noah's ``SOILPARM.TBL`` columns).
``set_value``
    How setting it with BMI after ``initialize`` compares with putting the same
    value in the config:

    =============  ==============================================================
    equivalent     proven bit-identical over a test run
    unexercised    the parameter changed nothing over the test run, so
                   equivalence is unproven
    untested       BMI-settable but not yet compared
    differs        results differ; change it in the config instead
    none           no BMI variable; config route only
    =============  ==============================================================
``note``
    Optional free text for reviewers.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Dict, Iterator, List, Optional, Union

import numpy as np

if TYPE_CHECKING:                                       # pragma: no cover
    from .model import Model

__all__ = ["Catalog", "CatalogMismatch", "Parameter", "STATUSES", "load_catalog", "CATALOG_DIR"]

CATALOG_DIR = Path(__file__).resolve().parent / "catalogs"

STATUSES = ("equivalent", "unexercised", "untested", "differs", "none")


class CatalogMismatch(RuntimeError):
    """The compiled library does not match the model's parameter catalog."""


@dataclass
class Parameter:
    name: str
    set_value: str
    dtype: Optional[str] = None
    length: Union[int, str, None] = 1
    units: Optional[str] = None
    config_key: Optional[str] = None
    source: Optional[str] = None
    note: Optional[str] = None

    def __post_init__(self):
        if self.set_value not in STATUSES:
            raise ValueError(f"{self.name}: set_value must be one of {STATUSES}, "
                             f"got {self.set_value!r}")
        if self.set_value == "none" and not self.config_key:
            raise ValueError(f"{self.name}: a config-only parameter needs a config_key")
        if self.bmi and not self.dtype:
            raise ValueError(f"{self.name}: a BMI parameter needs a dtype")

    @property
    def bmi(self) -> bool:
        """True when the parameter is a BMI variable (it can be read and set live)."""
        return self.set_value != "none"

    @property
    def safe_to_set(self) -> bool:
        """True when setting it after ``initialize`` is proven to match a config edit."""
        return self.set_value == "equivalent"

    _ORDER = ("name", "dtype", "length", "units", "config_key", "source", "set_value", "note")

    def as_dict(self) -> Dict:
        # length is always kept: null means "any length", and omitting it means 1.
        fields = asdict(self)
        return {k: fields[k] for k in self._ORDER if fields[k] is not None or k == "length"}


@dataclass
class Catalog:
    model: str
    parameters: Dict[str, Parameter]
    meta: Dict = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: Dict) -> "Catalog":
        params = {name: Parameter(name=name, **fields)
                  for name, fields in data.get("parameters", {}).items()}
        meta = {k: v for k, v in data.items() if k not in ("model", "parameters")}
        return cls(model=data["model"], parameters=params, meta=meta)

    @classmethod
    def read(cls, path: Union[str, Path]) -> "Catalog":
        return cls.from_dict(json.loads(Path(path).read_text(encoding="utf-8")))

    def to_dict(self) -> Dict:
        out = {"model": self.model, **self.meta}
        out["parameters"] = {}
        for name, p in self.parameters.items():
            row = p.as_dict()
            row.pop("name")
            out["parameters"][name] = row
        return out

    def write(self, path: Union[str, Path]) -> None:
        Path(path).write_text(json.dumps(self.to_dict(), indent=2) + "\n", encoding="utf-8")

    def __iter__(self) -> Iterator[Parameter]:
        return iter(self.parameters.values())

    def __getitem__(self, name: str) -> Parameter:
        try:
            return self.parameters[name]
        except KeyError:
            raise KeyError(f"{self.model} has no parameter {name!r} in its catalog") from None

    def __contains__(self, name: str) -> bool:
        return name in self.parameters

    def bmi_parameters(self) -> List[Parameter]:
        return [p for p in self if p.bmi]

    def by_config_key(self, key: str) -> Optional[Parameter]:
        for p in self:
            if p.config_key == key:
                return p
        return None

    def check(self, model: "Model") -> None:
        """Raise :class:`CatalogMismatch` unless every BMI entry matches the library.

        Checks that each name is known to the library, that its dtype matches,
        and that its length matches (exactly for a number; at least 1 when the
        length depends on the config). All mismatches are reported together.
        """
        problems = []
        for p in self.bmi_parameters():
            if not model.is_var(p.name):
                problems.append(f"{p.name}: not a variable of the library")
                continue
            try:
                dtype = model.var_dtype(p.name)
                length = model.var_length(p.name)
            except Exception as err:                    # noqa: BLE001
                problems.append(f"{p.name}: metadata query failed: {err}")
                continue
            if dtype != np.dtype(p.dtype):
                problems.append(f"{p.name}: dtype is {dtype}, catalog says {p.dtype}")
            if isinstance(p.length, int):
                if length != p.length:
                    problems.append(f"{p.name}: length is {length}, catalog says {p.length}")
            elif length < 1:
                problems.append(f"{p.name}: length is {length}")
        if problems:
            raise CatalogMismatch(
                f"{model.name}: the library does not match catalog {self.model!r}:\n  "
                + "\n  ".join(problems))


def load_catalog(key: str) -> Catalog:
    """The packaged catalog for model ``key`` (e.g. ``"cfe"``)."""
    from .models import get_spec

    spec = get_spec(key)
    if not spec.catalog:
        raise KeyError(f"model {key!r} has no parameter catalog")
    return Catalog.read(CATALOG_DIR / spec.catalog)
