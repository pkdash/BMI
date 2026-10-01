#! /usr/bin/env python
from importlib.metadata import version, PackageNotFoundError

try:
    __version__ = version("pymt_topmodel")
except PackageNotFoundError:
    __version__ = "0+unknown"

from .bmi import TOPMODEL

__all__ = [
    "TOPMODEL",
]
