#!/usr/bin/env bash
set -euo pipefail

# Reapply local customizations that Babelizer may overwrite.
# Assumes this script lives at the repository root and package is under ./pymt_sft

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_sft"

if [[ ! -d "${PKG_DIR}" ]]; then
  echo "ERROR: Expected package directory not found: ${PKG_DIR}" >&2
  exit 1
fi

echo "Reapplying patches in: ${PKG_DIR}"

# Install the generated BMI wrapper (.pyx + NumPy helpers) rendered by
# ../common/render_wrappers.py and vendored in ./wrapper; see ../common/README.md.
bash "${ROOT_DIR}/wrapper/install.sh" "${PKG_DIR}"

# ─── 2) Replace pkg_resources version lookup with importlib.metadata ──────────
cat > "${PKG_DIR}/pymt_sft/__init__.py" <<'PYEOF'
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
PYEOF

echo "- Replaced pymt_sft/__init__.py"

# ─── 3) Replace setup.py with portable SFT path-discovery version ─────────────
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


def _pkg_config_dirs(package_name="sftbmi"):
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


def _discover_sft_paths():
    env = os.environ
    sft_root     = env.get("SFT_ROOT", "")
    conda_prefix = env.get("CONDA_PREFIX", "")

    pkg_inc, pkg_lib = _pkg_config_dirs("sftbmi")

    include_candidates = [
        env.get("SFT_INCLUDE_DIR", ""),
        env.get("SFT_BMI_DIR", ""),
        os.path.join(sys.prefix, "include"),
        os.path.join(conda_prefix, "include") if conda_prefix else "",
        os.path.join(sft_root, "include") if sft_root else "",
        os.path.join(sft_root, "bmi")     if sft_root else "",
        os.path.join(sft_root, "src")     if sft_root else "",
        "/workspace/sft/include",
        "/workspace/sft/bmi",
        "/workspace/sft/src",
    ] + pkg_inc

    library_candidates = [
        env.get("SFT_LIB_DIR", ""),
        os.path.join(sys.prefix, "lib"),
        os.path.join(conda_prefix, "lib") if conda_prefix else "",
        os.path.join(sft_root, "build") if sft_root else "",
        os.path.join(sft_root, "lib")   if sft_root else "",
        "/workspace/sft/build",
        "/workspace/sft/lib",
    ] + pkg_lib

    return (
        _unique_existing(include_candidates),
        _unique_existing(library_candidates),
    )


include_dirs, library_dirs = _discover_sft_paths()

# Embed the native library's directory as an RPATH so `import pymt_sft` can
# locate libsftbmi.so at runtime without LD_LIBRARY_PATH (library_dirs above
# only affects link time). Not supported by MSVC (Windows).
runtime_library_dirs = []
if not sys.platform.startswith("win"):
    for d in [os.environ.get("SFT_RPATH", ""), os.environ.get("SFT_LIB_DIR", "")]:
        if d and Path(d).exists() and d not in runtime_library_dirs:
            runtime_library_dirs.append(d)

common_flags = {
    "include_dirs": [np.get_include(), *include_dirs],
    "library_dirs": library_dirs,
    "runtime_library_dirs": runtime_library_dirs,
    "define_macros": [("BMI_ACTIVE", None)],  # matches SFT CMakeLists
    "undef_macros": [],
    "extra_compile_args": ["-std=c++14"],
    "language": "c++",
}

if sys.platform.startswith("win"):
    common_flags["include_dirs"].append(
        os.path.join(sys.prefix, "Library", "include")
    )
    common_flags["library_dirs"].append(
        os.path.join(sys.prefix, "Library", "lib")
    )


def _extension_source():
    pyx_source = Path("pymt_sft/lib/sft.pyx")
    cpp_source = Path("pymt_sft/lib/sft.cpp")
    if cythonize is not None and pyx_source.exists():
        return str(pyx_source)
    if cpp_source.exists():
        return str(cpp_source)
    raise RuntimeError(
        "Cannot build pymt_sft: missing pymt_sft/lib/sft.cpp and Cython is "
        "not available to generate it from pymt_sft/lib/sft.pyx."
    )


ext_modules = [
    Extension(
        "pymt_sft.lib.sft",
        sources=[_extension_source()],
        libraries=["sftbmi"],
        **common_flags,
    ),
]

if cythonize is not None and ext_modules[0].sources[0].endswith(".pyx"):
    ext_modules = cythonize(ext_modules, language_level=3)

entry_points = {
    "pymt.plugins": [
        "SFT=pymt_sft.bmi:SFT",
    ]
}


def read(filename):
    with open(filename, "r", encoding="utf-8") as fp:
        return fp.read()


long_description = "\n\n".join(
    [read("README.rst"), read("CREDITS.rst"), read("CHANGES.rst")]
)

setup(
    name="pymt_sft",
    author="Pabitra Dash",
    author_email="pkdash_reena@hotmail.com",
    description="PyMT plugin for NOAA-OWP SoilFreezeThaw",
    long_description=long_description,
    version="0.1",
    url="https://github.com/NOAA-OWP/SoilFreezeThaw",
    project_urls={
        "Source": "https://github.com/pkdash/BMI/tree/main/SOIL-FREEZE-THAW/pymt_sft",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Science/Research",
        "License :: OSI Approved :: MIT License",
        "Operating System :: POSIX :: Linux",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.11",
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

echo "- Replaced setup.py"

# ─── 4) Fix MANIFEST.in: include generated .cpp in sdist, not exclude ─────────
MANIFEST_IN="${PKG_DIR}/MANIFEST.in"
if [[ -f "${MANIFEST_IN}" ]]; then
    sed -i \
        's/recursive-exclude pymt_sft \*\.cpp/recursive-include pymt_sft *.cpp/' \
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
echo "  - ${PKG_DIR}/pymt_sft/lib/sft.pyx  (generated BMI wrapper from ../common)"
echo "  - ${PKG_DIR}/pymt_sft/__init__.py"
echo "  - ${PKG_DIR}/setup.py"
echo "  - ${PKG_DIR}/MANIFEST.in"
echo
echo "Next steps:"
echo "  cd ${PKG_DIR}"
echo "  rm -rf build dist *.egg-info"
echo "  uv build"
