#!/usr/bin/env bash
set -euo pipefail

# Reapply local customizations that Babelizer may overwrite.
# Assumes this script lives at the repository root and package is under ./pymt_cfe

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_cfe"

if [[ ! -d "${PKG_DIR}" ]]; then
  echo "ERROR: Expected package directory not found: ${PKG_DIR}" >&2
  exit 1
fi

echo "Reapplying patches in: ${PKG_DIR}"

# 1) Replace pkg_resources version lookup with importlib.metadata
cat > "${PKG_DIR}/pymt_cfe/__init__.py" <<'PYEOF'
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
PYEOF

# 2) Restore portable CFE path discovery in setup.py
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


def _pkg_config_dirs(package_name="cfebmi"):
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


def _discover_cfe_paths():
    env = os.environ

    cfe_root = env.get("CFE_ROOT", "")
    conda_prefix = env.get("CONDA_PREFIX", "")

    pkg_inc, pkg_lib = _pkg_config_dirs("cfebmi")

    include_candidates = [
        env.get("CFE_INCLUDE_DIR", ""),
        env.get("CFE_BMI_DIR", ""),
        env.get("CFE_SRC_DIR", ""),
        env.get("CFE_SMP_INCLUDE_DIR", ""),
        os.path.join(sys.prefix, "include"),
        os.path.join(conda_prefix, "include") if conda_prefix else "",
        os.path.join(cfe_root, "include") if cfe_root else "",
        os.path.join(cfe_root, "bmi") if cfe_root else "",
        os.path.join(cfe_root, "src") if cfe_root else "",
        os.path.join(cfe_root, "extern", "SoilMoistureProfiles", "include") if cfe_root else "",
        "/workspace/cfe/include",
        "/workspace/cfe/bmi",
        "/workspace/cfe/src",
        "/workspace/cfe/extern/SoilMoistureProfiles/include",
    ] + pkg_inc

    library_candidates = [
        env.get("CFE_LIB_DIR", ""),
        os.path.join(sys.prefix, "lib"),
        os.path.join(conda_prefix, "lib") if conda_prefix else "",
        os.path.join(cfe_root, "build") if cfe_root else "",
        os.path.join(cfe_root, "lib") if cfe_root else "",
        "/workspace/cfe/build",
        "/workspace/cfe/lib",
    ] + pkg_lib

    include_dirs = _unique_existing(include_candidates)
    library_dirs = _unique_existing(library_candidates)

    return include_dirs, library_dirs


include_dirs, library_dirs = _discover_cfe_paths()

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
    pyx_source = Path("pymt_cfe/lib/cfe.pyx")
    c_source = Path("pymt_cfe/lib/cfe.c")

    if cythonize is not None and pyx_source.exists():
        return str(pyx_source)
    if c_source.exists():
        return str(c_source)

    raise RuntimeError(
        "Cannot build pymt_cfe: missing pymt_cfe/lib/cfe.c and Cython is "
        "not available to generate it from pymt_cfe/lib/cfe.pyx."
    )

# Locate directories under Windows %LIBRARY_PREFIX%.
if sys.platform.startswith("win"):
    common_flags["include_dirs"].append(os.path.join(sys.prefix, "Library", "include"))
    common_flags["library_dirs"].append(os.path.join(sys.prefix, "Library", "lib"))

ext_modules = [
    Extension(
        "pymt_cfe.lib.cfe",
        [_extension_source()],
        libraries=libraries + ["cfebmi"],
        **common_flags,
    ),
]

if cythonize is not None and ext_modules[0].sources[0].endswith(".pyx"):
    ext_modules = cythonize(ext_modules, language_level=3)

entry_points = {
    "pymt.plugins": [
        "CFE=pymt_cfe.bmi:CFE",
    ]
}


def read(filename):
    with open(filename, "r", encoding="utf-8") as fp:
        return fp.read()


long_description = "\n\n".join([read("README.rst"), read("CREDITS.rst"), read("CHANGES.rst")])


setup(
    name="pymt_cfe",
    author="Pabitra Dash",
    author_email="pkdash_reena@hotmail.com",
    description="PyMT plugin for pymt_cfe",
    long_description=long_description,
    version="0.1",
    url="https://github.com/pkdash/pymt_cfe",
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
    "recursive-exclude pymt_cfe *.c",
    "recursive-include pymt_cfe *.c",
)
if "recursive-include pymt_cfe *.c" not in text:
    text = text.rstrip() + "\nrecursive-include pymt_cfe *.c\n"
path.write_text(text)
PYEOF
fi

echo "Done. Patched:"
echo "  - ${PKG_DIR}/pymt_cfe/__init__.py"
echo "  - ${PKG_DIR}/setup.py"
echo "  - ${PKG_DIR}/MANIFEST.in"
echo
echo "Next steps:"
echo "  cd ${PKG_DIR}"
echo "  rm -rf build dist *.egg-info"
echo "  uv build"
