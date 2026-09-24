#! /usr/bin/env python
from importlib.metadata import version, PackageNotFoundError

try:
    __version__ = version("pymt_sft")
except PackageNotFoundError:
    __version__ = "0+unknown"

from .bmi import SFT

__all__ = [
    "SFT",
]
