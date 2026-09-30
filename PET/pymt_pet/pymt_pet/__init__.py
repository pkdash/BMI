#! /usr/bin/env python
from importlib.metadata import version, PackageNotFoundError

try:
    __version__ = version("pymt_pet")
except PackageNotFoundError:
    __version__ = "0+unknown"

from .bmi import PET

__all__ = [
    "PET",
]
