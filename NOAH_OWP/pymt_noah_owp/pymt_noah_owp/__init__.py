#! /usr/bin/env python
from importlib.metadata import version, PackageNotFoundError

try:
    __version__ = version("pymt_noah_owp")
except PackageNotFoundError:
    __version__ = "0+unknown"

from .bmi import NOAH_OWP

__all__ = [
    "NOAH_OWP",
]
