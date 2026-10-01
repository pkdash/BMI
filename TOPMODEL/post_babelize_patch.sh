#!/usr/bin/env bash
set -euo pipefail

# Reapply local customizations that Babelizer may overwrite.
# Assumes this script lives at the repository root and package is under ./pymt_topmodel

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_topmodel"

if [[ ! -d "${PKG_DIR}" ]]; then
  echo "ERROR: Expected package directory not found: ${PKG_DIR}" >&2
  exit 1
fi

echo "Reapplying patches in: ${PKG_DIR}"

# 1) Replace pkg_resources version lookup with importlib.metadata
cat > "${PKG_DIR}/pymt_topmodel/__init__.py" <<'PYEOF'
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
PYEOF

# 2) Restore portable TOPMODEL path discovery in setup.py
cat > "${PKG_DIR}/setup.py" <<'PYEOF'
#! /usr/bin/env python
import os
import shlex
import subprocess
import sys
from pathlib import Path

import numpy as np
from setuptools import Extension, find_packages, setup

try:
    from Cython.Build import cythonize
except ImportError:
    cythonize = None


def _unique_existing(paths):
    seen = set()
    out = []
    for p in paths:
        if not p:
            continue
        p = str(Path(p))
        if p not in seen and Path(p).exists():
            seen.add(p)
            out.append(p)
    return out


def _pkg_config_dirs(package_name="topmodelbmi"):
    include_dirs = []
    library_dirs = []

    try:
        cflags = subprocess.check_output(
            ["pkg-config", "--cflags", package_name],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        for token in shlex.split(cflags):
            if token.startswith("-I") and len(token) > 2:
                include_dirs.append(token[2:])
    except Exception:
        pass

    try:
        lflags = subprocess.check_output(
            ["pkg-config", "--libs-only-L", package_name],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        for token in shlex.split(lflags):
            if token.startswith("-L") and len(token) > 2:
                library_dirs.append(token[2:])
    except Exception:
        pass

    return include_dirs, library_dirs


def _discover_topmodel_paths():
    env = os.environ

    topmodel_root = env.get("TOPMODEL_ROOT", "")
    conda_prefix = env.get("CONDA_PREFIX", "")

    pkg_inc, pkg_lib = _pkg_config_dirs("topmodelbmi")

    include_candidates = [
        env.get("TOPMODEL_INCLUDE_DIR", ""),
        os.path.join(sys.prefix, "include"),
        os.path.join(conda_prefix, "include") if conda_prefix else "",
        os.path.join(topmodel_root, "include") if topmodel_root else "",
        "/workspace/topmodel/include",
    ] + pkg_inc

    library_candidates = [
        env.get("TOPMODEL_LIB_DIR", ""),
        os.path.join(sys.prefix, "lib"),
        os.path.join(conda_prefix, "lib") if conda_prefix else "",
        os.path.join(topmodel_root, "build") if topmodel_root else "",
        os.path.join(topmodel_root, "cmake_build") if topmodel_root else "",
        os.path.join(topmodel_root, "lib") if topmodel_root else "",
        "/workspace/topmodel/build",
        "/workspace/topmodel/cmake_build",
        "/workspace/topmodel/lib",
    ] + pkg_lib

    include_dirs = _unique_existing(include_candidates)
    library_dirs = _unique_existing(library_candidates)

    return include_dirs, library_dirs


include_dirs, library_dirs = _discover_topmodel_paths()

common_flags = {
    "include_dirs": [np.get_include(), *include_dirs],
    "library_dirs": library_dirs,
    "define_macros": [],
    "undef_macros": [],
    "extra_compile_args": [],
    "language": "c",
}

libraries = []


def _extension_source():
    pyx_source = Path("pymt_topmodel/lib/topmodel.pyx")
    c_source = Path("pymt_topmodel/lib/topmodel.c")

    if cythonize is not None and pyx_source.exists():
        return str(pyx_source)
    if c_source.exists():
        return str(c_source)

    raise RuntimeError(
        "Cannot build pymt_topmodel: missing pymt_topmodel/lib/topmodel.c and Cython is "
        "not available to generate it from pymt_topmodel/lib/topmodel.pyx."
    )

# Locate directories under Windows %LIBRARY_PREFIX%.
if sys.platform.startswith("win"):
    common_flags["include_dirs"].append(os.path.join(sys.prefix, "Library", "include"))
    common_flags["library_dirs"].append(os.path.join(sys.prefix, "Library", "lib"))

ext_modules = [
    Extension(
        "pymt_topmodel.lib.topmodel",
        [_extension_source()],
        libraries=libraries + ["topmodelbmi"],
        **common_flags,
    ),
]

if cythonize is not None and ext_modules[0].sources[0].endswith(".pyx"):
    ext_modules = cythonize(ext_modules, language_level=3)

entry_points = {
    "pymt.plugins": [
        "TOPMODEL=pymt_topmodel.bmi:TOPMODEL",
    ]
}


def read(filename):
    with open(filename, "r", encoding="utf-8") as fp:
        return fp.read()


long_description = "\n\n".join([read("README.rst"), read("CREDITS.rst"), read("CHANGES.rst")])


setup(
    name="pymt_topmodel",
    author="Vaishali Swaminathan",
    author_email="",
    description="PyMT plugin for pymt_topmodel",
    long_description=long_description,
    version="0.1",
    url="https://github.com/vaishswami/pymt_topmodel",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Science/Research",
        "License :: OSI Approved :: MIT License",
        "Operating System :: MacOS :: MacOS X",
        "Operating System :: POSIX :: Linux",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.8",
    ],
    keywords=["bmi", "pymt"],
    install_requires=open("requirements.txt", "r").read().splitlines(),
    setup_requires=["cython"],
    ext_modules=ext_modules,
    packages=find_packages(),
    entry_points=entry_points,
    include_package_data=True,
)
PYEOF

# 3) Keep generated C sources in source distributions. They are useful when
# installing without build isolation or without Cython available.
MANIFEST_IN="${PKG_DIR}/MANIFEST.in"
if [[ -f "${MANIFEST_IN}" ]]; then
python - "${MANIFEST_IN}" <<'PYEOF'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace(
    "recursive-exclude pymt_topmodel *.c",
    "recursive-include pymt_topmodel *.c",
)
if "recursive-include pymt_topmodel *.c" not in text:
    text = text.rstrip() + "\nrecursive-include pymt_topmodel *.c\n"
path.write_text(text)
PYEOF
fi

echo "Done. Patched:"
echo "  - ${PKG_DIR}/pymt_topmodel/__init__.py"
echo "  - ${PKG_DIR}/setup.py"
echo "  - ${PKG_DIR}/MANIFEST.in"
echo
echo "Next steps:"
echo "  cd ${PKG_DIR}"
echo "  rm -rf build dist *.egg-info"
echo "  uv build"
