from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("pymt_sac_sma")
except PackageNotFoundError:
    __version__ = "0+unknown"

from .bmi import SAC_SMA

__all__ = ["SAC_SMA"]
