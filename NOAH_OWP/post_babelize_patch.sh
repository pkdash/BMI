#!/usr/bin/env bash
set -euo pipefail

# Reapply local customizations that Babelizer may overwrite.
# Assumes this script lives at NOAH_OWP root and package is under ./pymt_noah_owp

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_noah_owp"

if [[ ! -d "${PKG_DIR}" ]]; then
  echo "ERROR: Expected package directory not found: ${PKG_DIR}" >&2
  exit 1
fi

echo "Reapplying patches in: ${PKG_DIR}"

# 0) Fix Babelizer module name mismatch:
#    Babelizer generates 'use surfacebmi' from library name, but the actual
#    Noah Fortran module is 'bminoahowp'. Patch the generated interop file.
INTEROP_F90="${PKG_DIR}/pymt_noah_owp/lib/bmi_interoperability.f90"
if [[ -f "${INTEROP_F90}" ]]; then
  # Babelizer generates 'use surfacebmi' from library name, but the actual
  # Noah Fortran module is 'bminoahowp'.
  sed -i 's/^  use surfacebmi$/  use bminoahowp/' "${INTEROP_F90}"
  # Babelizer generates 'type (register_bmi)' as the model array type, but
  # the actual Noah derived type is 'bmi_noahowp'.
  sed -i 's/type (register_bmi)/type (bmi_noahowp)/g' "${INTEROP_F90}"
  echo "  - Patched bmi_interoperability.f90: module name + derived type name"
fi

# 1) Replace pkg_resources version lookup with importlib.metadata
cat > "${PKG_DIR}/pymt_noah_owp/__init__.py" <<'PYEOF'
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
PYEOF

# 2) Remove numpy.distutils dependency and use FC/gfortran directly for
#    bmi_interoperability.f90 compilation.
cat > "${PKG_DIR}/setup.py" <<'PYEOF'
#! /usr/bin/env python
import contextlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from setuptools import Extension, find_packages, setup
from setuptools.command.build_ext import build_ext as _build_ext


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


def _discover_noah_paths():
    env = os.environ
    noah_root = env.get("NOAH_ROOT", "")

    include_candidates = [
        env.get("NOAH_INCLUDE_DIR", ""),
        env.get("NOAH_BMI_DIR", ""),
        env.get("NOAH_MOD_DIR", ""),
        os.path.join(sys.prefix, "include"),
        os.path.join(noah_root, "include") if noah_root else "",
        os.path.join(noah_root, "src") if noah_root else "",
        os.path.join(noah_root, "bmi") if noah_root else "",
        os.path.join(noah_root, "cmake_build", "mod") if noah_root else "",
        "/workspace/noah-owp-modular/include",
        "/workspace/noah-owp-modular/src",
        "/workspace/noah-owp-modular/bmi",
        "/workspace/noah-owp-modular/cmake_build/mod",
    ]

    library_candidates = [
        env.get("NOAH_LIB_DIR", ""),
        os.path.join(sys.prefix, "lib"),
        os.path.join(noah_root, "build") if noah_root else "",
        os.path.join(noah_root) if noah_root else "",
        os.path.join(noah_root, "cmake_build") if noah_root else "",
        "/workspace/noah-owp-modular/build",
        "/workspace/noah-owp-modular",
        "/workspace/noah-owp-modular/cmake_build",
    ]

    return _unique_existing(include_candidates), _unique_existing(library_candidates)


def _find_fortran_compiler():
    candidates = [
        os.environ.get("FC", "").strip(),
        "gfortran",
        "ifort",
        "flang",
        "nvfortran",
        "f95",
        "f90",
    ]
    for c in candidates:
        if not c:
            continue
        exe = shutil.which(c)
        if exe:
            return exe
    raise RuntimeError(
        "No Fortran compiler found. Set FC or install gfortran/ifort/flang in the build environment."
    )


include_dirs, library_dirs = _discover_noah_paths()

common_flags = {
    "include_dirs": [np.get_include(), *include_dirs],
    "library_dirs": library_dirs,
    "define_macros": [],
    "undef_macros": [],
    "extra_compile_args": [],
    "language": "c",
}

libraries = []

# Locate directories under Windows %LIBRARY_PREFIX%.
if sys.platform.startswith("win"):
    common_flags["include_dirs"].append(os.path.join(sys.prefix, "Library", "include"))
    common_flags["library_dirs"].append(os.path.join(sys.prefix, "Library", "lib"))

ext_modules = [
    Extension(
        "pymt_noah_owp.lib.noah_owp",
        ["pymt_noah_owp/lib/noah_owp.pyx"],
        libraries=libraries + ["surfacebmi"],
        extra_objects=["pymt_noah_owp/lib/bmi_interoperability.o"],
        **common_flags,
    ),
]

entry_points = {
    "pymt.plugins": [
        "NOAH_OWP=pymt_noah_owp.bmi:NOAH_OWP",
    ]
}


@contextlib.contextmanager
def as_cwd(path):
    prev_cwd = os.getcwd()
    os.chdir(path)
    yield
    os.chdir(prev_cwd)


def build_interoperability():
    compiler = _find_fortran_compiler()

    cmd = [compiler, "-c"]
    if not sys.platform.startswith("win"):
        cmd.append("-fPIC")

    for include_dir in common_flags["include_dirs"]:
        if os.path.isabs(include_dir) is False:
            include_dir = os.path.join(sys.prefix, "include", include_dir)
        cmd.append(f"-I{include_dir}")

    cmd.append("bmi_interoperability.f90")
    subprocess.check_call(cmd)


class build_ext(_build_ext):

    def run(self):
        with as_cwd("pymt_noah_owp/lib"):
            build_interoperability()
        _build_ext.run(self)


def read(filename):
    with open(filename, "r", encoding="utf-8") as fp:
        return fp.read()


long_description = "\n\n".join(
    [read("README.rst"), read("CREDITS.rst"), read("CHANGES.rst")]
)


setup(
    name="pymt_noah_owp",
    author="Pabitra Dash",
    author_email="pkdash_reena@hotmail.com",
    description="PyMT plugin for pymt_noah_owp",
    long_description=long_description,
    version="0.1",
    url="https://github.com/pkdash/pymt_noah_owp",
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
    cmdclass=dict(build_ext=build_ext),
    packages=find_packages(),
    entry_points=entry_points,
    include_package_data=True,
)
PYEOF

# 3) Ensure Fortran/C interop sources are packaged in sdist
MANIFEST_FILE="${PKG_DIR}/MANIFEST.in"
if [[ -f "${MANIFEST_FILE}" ]]; then
  grep -q "recursive-include pymt_noah_owp .*\\*.f90" "${MANIFEST_FILE}" || \
    echo "recursive-include pymt_noah_owp *.f90" >> "${MANIFEST_FILE}"
  grep -q "recursive-include pymt_noah_owp .*\\*.h" "${MANIFEST_FILE}" || \
    echo "recursive-include pymt_noah_owp *.h" >> "${MANIFEST_FILE}"
fi

echo "Done. Patched:"
echo "  - ${PKG_DIR}/pymt_noah_owp/__init__.py"
echo "  - ${PKG_DIR}/setup.py"
echo "  - ${PKG_DIR}/MANIFEST.in (ensure *.f90, *.h included)"
