"""Set up and parameterize BMI models through their pymt_* Python wrappers.

BMI-generic: nothing here knows about any particular framework. ngen-specific
glue (realization files, running ngen) lives in ngen's ``tools/ngen-bmi``.
"""

from .catalog import Catalog, CatalogMismatch, Parameter, load_catalog
from .config_files import KeyValueConfig, NamelistConfig, TopmodelConfig, open_config
from .model import Model, chatter_to_stderr, open_model
from .models import MODELS, ModelSpec, get_spec

__all__ = [
    "Catalog", "CatalogMismatch", "Parameter", "load_catalog",
    "KeyValueConfig", "NamelistConfig", "TopmodelConfig", "open_config",
    "Model", "chatter_to_stderr", "open_model",
    "MODELS", "ModelSpec", "get_spec",
]

try:
    from importlib.metadata import version

    __version__ = version("bmi-setup")
except Exception:                                       # noqa: BLE001
    __version__ = "0+unknown"
