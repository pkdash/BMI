from importlib.metadata import PackageNotFoundError, version
try:
    __version__ = version("pymt_lasam")
except PackageNotFoundError:
    __version__ = "0+unknown"
from .bmi import LASAM
__all__ = ["LASAM"]
