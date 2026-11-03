from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("pymt_ueb")
except PackageNotFoundError:
    __version__ = "0+unknown"

from .bmi import UEB

__all__ = ["UEB"]
