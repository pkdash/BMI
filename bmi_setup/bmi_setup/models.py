"""Which wrapper class, parameter catalog and config codec belong to each model.

Keys match the model keys in ngen's ``tools/bmi-wrappers/wrappers.json`` so the
two can be joined on them. A model without a catalog can still be opened; it
just has no parameter metadata or catalog check.
"""

from __future__ import annotations

import importlib
from dataclasses import dataclass
from typing import Dict, Optional

__all__ = ["ModelSpec", "MODELS", "get_spec", "load_class"]


@dataclass(frozen=True)
class ModelSpec:
    key: str
    import_path: str
    class_name: str
    codec: Optional[str] = None       # class name in bmi_setup.config_files
    catalog: Optional[str] = None     # file name in bmi_setup/catalogs


MODELS: Dict[str, ModelSpec] = {s.key: s for s in (
    ModelSpec("cfe", "pymt_cfe", "CFE", "KeyValueConfig", "cfe.json"),
    ModelSpec("noah", "pymt_noah_owp", "NOAH_OWP", "NamelistConfig", "noah.json"),
    ModelSpec("pet", "pymt_pet", "PET", "KeyValueConfig", "pet.json"),
    ModelSpec("topmodel", "pymt_topmodel", "TOPMODEL", "TopmodelConfig", "topmodel.json"),
    ModelSpec("lasam", "pymt_lasam", "LASAM"),
    ModelSpec("sac_sma", "pymt_sac_sma", "SAC_SMA"),
    ModelSpec("sft", "pymt_sft", "SFT"),
    ModelSpec("smp", "pymt_smp", "SMP"),
    ModelSpec("snow17", "pymt_snow17", "SNOW17"),
    ModelSpec("ueb", "pymt_ueb", "UEB"),
)}


def get_spec(key: str) -> ModelSpec:
    try:
        return MODELS[key]
    except KeyError:
        raise KeyError(f"unknown model {key!r}; known models: {', '.join(sorted(MODELS))}") from None


def load_class(key: str):
    """Import and return the wrapper class for ``key`` (e.g. ``pymt_cfe.CFE``)."""
    spec = get_spec(key)
    try:
        module = importlib.import_module(spec.import_path)
    except ImportError as err:
        raise ImportError(f"model {key!r} needs the {spec.import_path} wrapper, "
                          f"which cannot be imported: {err}") from err
    return getattr(module, spec.class_name)
