#! /usr/bin/env python
from importlib.metadata import version, PackageNotFoundError
try:
    __version__ = version("pymt_snow17")
except PackageNotFoundError:
    __version__ = "0+unknown"
from .bmi import SNOW17
__all__ = ["SNOW17"]
