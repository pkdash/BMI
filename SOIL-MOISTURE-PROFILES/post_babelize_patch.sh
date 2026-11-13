#!/usr/bin/env bash
set -euo pipefail

# Reapply local customizations that Babelizer may overwrite.
# Assumes this script lives at the repository root and package is under ./pymt_smp

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_smp"

if [[ ! -d "${PKG_DIR}" ]]; then
  echo "ERROR: Expected package directory not found: ${PKG_DIR}" >&2
  exit 1
fi

echo "Reapplying patches in: ${PKG_DIR}"

# Install the generated BMI wrapper (.pyx + NumPy helpers) rendered by
# ../common/render_wrappers.py and vendored in ./wrapper; see ../common/README.md.
bash "${ROOT_DIR}/wrapper/install.sh" "${PKG_DIR}"

cat > "${PKG_DIR}/pymt_smp/__init__.py" <<'PYEOF'
#! /usr/bin/env python
from importlib.metadata import version, PackageNotFoundError

try:
    __version__ = version("pymt_smp")
except PackageNotFoundError:
    __version__ = "0+unknown"

from .bmi import SMP

__all__ = [
    "SMP",
]
PYEOF

echo "- Replaced pymt_smp/__init__.py"

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


def _pkg_config_dirs(package_name="smpbmi"):
    include_dirs = []
    library_dirs = []
    try:
        cflags = subprocess.check_output(
            ["pkg-config", "--cflags", package_name],
            text=True, stderr=subprocess.DEVNULL,
        ).strip()
        for token in shlex.split(cflags):
            if token.startswith("-I") and len(token) > 2:
                include_dirs.append(token[2:])
    except Exception:
        pass
    try:
        lflags = subprocess.check_output(
            ["pkg-config", "--libs-only-L", package_name],
            text=True, stderr=subprocess.DEVNULL,
        ).strip()
        for token in shlex.split(lflags):
            if token.startswith("-L") and len(token) > 2:
                library_dirs.append(token[2:])
    except Exception:
        pass
    return include_dirs, library_dirs


def _discover_smp_paths():
    env = os.environ
    smp_root = env.get("SMP_ROOT", "")
    conda_prefix = env.get("CONDA_PREFIX", "")

    pkg_inc, pkg_lib = _pkg_config_dirs("smpbmi")

    include_candidates = [
        env.get("SMP_INCLUDE_DIR", ""),
        env.get("SMP_BMI_DIR", ""),
        os.path.join(sys.prefix, "include"),
        os.path.join(conda_prefix, "include") if conda_prefix else "",
        os.path.join(smp_root, "include") if smp_root else "",
        os.path.join(smp_root, "bmi") if smp_root else "",
        os.path.join(smp_root, "src") if smp_root else "",
        "/workspace/smp/include",
        "/workspace/smp/bmi",
        "/workspace/smp/src",
    ] + pkg_inc

    library_candidates = [
        env.get("SMP_LIB_DIR", ""),
        os.path.join(sys.prefix, "lib"),
        os.path.join(conda_prefix, "lib") if conda_prefix else "",
        os.path.join(smp_root, "build") if smp_root else "",
        os.path.join(smp_root, "lib") if smp_root else "",
        "/workspace/smp/build",
        "/workspace/smp/lib",
    ] + pkg_lib

    return _unique_existing(include_candidates), _unique_existing(library_candidates)


include_dirs, library_dirs = _discover_smp_paths()

runtime_library_dirs = []
for d in [os.environ.get("SMP_RPATH", ""), os.environ.get("SMP_LIB_DIR", "")]:
    if d and Path(d).exists() and d not in runtime_library_dirs:
        runtime_library_dirs.append(d)

common_flags = {
    "include_dirs": [np.get_include(), *include_dirs],
    "library_dirs": library_dirs,
    "runtime_library_dirs": runtime_library_dirs,
    "define_macros": [("BMI_ACTIVE", None), ("NGEN", None)],
    "undef_macros": [],
    "extra_compile_args": ["-std=c++14"],
    "language": "c++",
}

if sys.platform.startswith("win"):
    common_flags["include_dirs"].append(os.path.join(sys.prefix, "Library", "include"))
    common_flags["library_dirs"].append(os.path.join(sys.prefix, "Library", "lib"))


def _extension_source():
    pyx_source = Path("pymt_smp/lib/smp.pyx")
    cpp_source = Path("pymt_smp/lib/smp.cpp")
    if cythonize is not None and pyx_source.exists():
        return str(pyx_source)
    if cpp_source.exists():
        return str(cpp_source)
    raise RuntimeError(
        "Cannot build pymt_smp: missing pymt_smp/lib/smp.cpp and Cython is "
        "not available to generate it from pymt_smp/lib/smp.pyx."
    )


ext_modules = [
    Extension(
        "pymt_smp.lib.smp",
        sources=[_extension_source()],
        libraries=["smpbmi"],
        **common_flags,
    ),
]

if cythonize is not None and ext_modules[0].sources[0].endswith(".pyx"):
    ext_modules = cythonize(ext_modules, language_level=3)

entry_points = {
    "pymt.plugins": [
        "SMP=pymt_smp.bmi:SMP",
    ]
}


def read(filename):
    with open(filename, "r", encoding="utf-8") as fp:
        return fp.read()


long_description = "\n\n".join(
    [read("README.rst"), read("CREDITS.rst"), read("CHANGES.rst")]
)

setup(
    name="pymt_smp",
    author="Vaishali Swaminathan",
    author_email="",
    description="PyMT plugin for NOAA-OWP Soil Moisture Profiles",
    long_description=long_description,
    version="0.1",
    url="https://github.com/NOAA-OWP/SoilMoistureProfiles",
    project_urls={
        "Source": "https://github.com/pkdash/BMI/tree/main/SOIL-MOISTURE-PROFILES/pymt_smp",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Science/Research",
        "License :: OSI Approved :: MIT License",
        "Operating System :: POSIX :: Linux",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.11",
    ],
    keywords=["bmi", "pymt", "soil moisture profiles", "NextGen"],
    install_requires=open("requirements.txt", "r").read().splitlines(),
    setup_requires=["cython"],
    ext_modules=ext_modules,
    packages=find_packages(),
    entry_points=entry_points,
    include_package_data=True,
)
PYEOF

echo "- Replaced setup.py"

MANIFEST_IN="${PKG_DIR}/MANIFEST.in"
if [[ -f "${MANIFEST_IN}" ]]; then
    sed -i \
        's/recursive-exclude pymt_smp \*\.cpp/recursive-include pymt_smp *.cpp/' \
        "${MANIFEST_IN}"
    echo "- Fixed MANIFEST.in (.cpp include)"
fi

echo
# Pin numpy<2 in the build requirements. The primary consumer (NOAA-OWP/ngen)
# hard-rejects numpy>=2.0.0 at CMake configure time, so the extension must be
# built against the same major version. Babelizer regenerates pyproject.toml
# with an unpinned numpy.
PYPROJECT="${PKG_DIR}/pyproject.toml"
if [[ -f "${PYPROJECT}" ]]; then
python - "${PYPROJECT}" <<'PYEOF'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
if '"numpy<2"' not in text:
    text = text.replace('"numpy"', '"numpy<2"', 1)
    comment = (
        "# numpy is pinned below 2 deliberately. The primary consumer of this wrapper\n"
        "# (NOAA-OWP/ngen) hard-rejects numpy>=2.0.0 at CMake configure time, so the\n"
        "# extension must be built against the same major version it will be imported\n"
        "# alongside. Leaving this unpinned also makes isolated pip builds drift as new\n"
        "# numpy majors are released.\n"
    )
    text = text.replace("requires = [", comment + "requires = [", 1)
path.write_text(text)
PYEOF
fi

echo "Done. Patched:"
echo "  - ${PKG_DIR}/pymt_smp/lib/smp.pyx  (generated BMI wrapper from ../common)"
echo "  - ${PKG_DIR}/pymt_smp/__init__.py"
echo "  - ${PKG_DIR}/setup.py"
echo "  - ${PKG_DIR}/MANIFEST.in"
echo
echo "Next steps:"
echo "  cd ${PKG_DIR}"
echo "  rm -rf build dist *.egg-info"
echo "  uv build"
