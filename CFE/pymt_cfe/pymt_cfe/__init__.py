#! /usr/bin/env python
from importlib.metadata import version, PackageNotFoundError

try:
    __version__ = version("pymt_cfe")
except PackageNotFoundError:
    __version__ = "0+unknown"

from .bmi import CFE

__all__ = [
    "CFE",
]
