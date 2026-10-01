#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_sac_sma"

[[ -d "${PKG_DIR}" ]] || {
  echo "ERROR: Expected generated package directory not found: ${PKG_DIR}" >&2
  exit 1
}

INTEROP_F90="${PKG_DIR}/pymt_sac_sma/lib/bmi_interoperability.f90"

if [[ ! -f "${INTEROP_F90}" ]]; then
  echo "ERROR: Babelizer interoperability source not found: ${INTEROP_F90}" >&2
  exit 1
fi

# Babelizer derives these identifiers from the library name and entry point.
# Sac-SMA's actual Fortran module/type are:
#   module bmi_sac_module
#   type, extends(bmi) :: bmi_sac
python - "${INTEROP_F90}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

# Handle whichever module declaration Babelizer 0.3.x generated.
text = re.sub(
    r"(?m)^\s*use\s+sacbmi\s*$",
    "  use bmi_sac_module",
    text,
)
text = re.sub(
    r"(?m)^\s*use\s+register_bmi\s*$",
    "  use bmi_sac_module",
    text,
)

# Replace generated model-array derived type with Sac-SMA's real type.
text = re.sub(
    r"type\s*\(\s*register_bmi\s*\)",
    "type (bmi_sac)",
    text,
)
text = re.sub(
    r"type\s*\(\s*sacbmi\s*\)",
    "type (bmi_sac)",
    text,
)

path.write_text(text)
PY

echo "- Patched Fortran module/type in bmi_interoperability.f90"

cat > "${PKG_DIR}/pymt_sac_sma/__init__.py" <<'PYEOF'
from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("pymt_sac_sma")
except PackageNotFoundError:
    __version__ = "0+unknown"

from .bmi import SAC_SMA

__all__ = ["SAC_SMA"]
PYEOF

cat > "${PKG_DIR}/setup.py" <<'PYEOF'
#!/usr/bin/env python
import contextlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from setuptools import Extension, find_packages, setup
from setuptools.command.build_ext import build_ext as _build_ext

try:
    from Cython.Build import cythonize
except ImportError:
    cythonize = None


def unique_existing(paths):
    out, seen = [], set()
    for value in paths:
        if not value:
            continue
        path = str(Path(value).expanduser())
        if path not in seen and Path(path).exists():
            seen.add(path)
            out.append(path)
    return out


def discover_paths():
    env = os.environ
    root = env.get("SAC_SMA_ROOT", "")
    lib_dir = env.get("SAC_SMA_LIB_DIR", "")
    bmi_dir = env.get("SAC_SMA_BMI_DIR", "")
    iso_root = env.get("ISO_C_FORTRAN_BMI_PATH", "")
    conda = env.get("CONDA_PREFIX", "")

    include_candidates = [
        env.get("SAC_SMA_INCLUDE_DIR", ""),
        bmi_dir,
        f"{lib_dir}/mod" if lib_dir else "",
        lib_dir,
        f"{root}/src/bmi" if root else "",
        f"{root}/cmake_build" if root else "",
        f"{root}/cmake_build/mod" if root else "",
        iso_root,
        f"{sys.prefix}/include",
        f"{conda}/include" if conda else "",
        "/workspace/sac-sma/cmake_build",
        "/workspace/sac-sma/cmake_build/mod",
        "/workspace/sac-sma/src/bmi",
        "/workspace/ngen/extern/iso_c_fortran_bmi",
    ]

    library_candidates = [
        lib_dir,
        f"{root}/cmake_build" if root else "",
        f"{root}/build" if root else "",
        f"{sys.prefix}/lib",
        f"{conda}/lib" if conda else "",
        "/workspace/sac-sma/cmake_build",
    ]

    return unique_existing(include_candidates), unique_existing(library_candidates)


def find_fortran_compiler():
    for candidate in (
        os.environ.get("FC", ""),
        "gfortran",
        "/usr/bin/gfortran",
        "flang",
        "ifort",
        "nvfortran",
        "f95",
        "f90",
    ):
        if not candidate:
            continue
        executable = shutil.which(candidate)
        if executable:
            return executable
    raise RuntimeError("No Fortran compiler found. Install gfortran or set FC.")


include_dirs, library_dirs = discover_paths()

pyx_source = Path("pymt_sac_sma/lib/sac_sma.pyx")
c_source = Path("pymt_sac_sma/lib/sac_sma.c")
if cythonize is not None and pyx_source.exists():
    extension_source = str(pyx_source)
elif c_source.exists():
    extension_source = str(c_source)
else:
    raise RuntimeError("Missing sac_sma.pyx and generated sac_sma.c")

interop_object = "pymt_sac_sma/lib/bmi_interoperability.o"

extension = Extension(
    "pymt_sac_sma.lib.sac_sma",
    sources=[extension_source],
    include_dirs=[np.get_include(), *include_dirs],
    library_dirs=library_dirs,
    libraries=["sacbmi", "gfortran"],
    extra_objects=[interop_object],
    language="c",
)

ext_modules = [extension]
if cythonize is not None and extension_source.endswith(".pyx"):
    ext_modules = cythonize(ext_modules, language_level=3)


@contextlib.contextmanager
def as_cwd(path):
    previous = os.getcwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(previous)


def build_interoperability():
    compiler = find_fortran_compiler()
    command = [compiler, "-c", "-fPIC"]

    for include_dir in include_dirs:
        command.append(f"-I{include_dir}")

    command.append("bmi_interoperability.f90")
    print("Compiling interoperability source:")
    print(" ".join(command))
    subprocess.check_call(command)


class build_ext(_build_ext):
    def run(self):
        with as_cwd("pymt_sac_sma/lib"):
            build_interoperability()
        super().run()


setup(
    name="pymt_sac_sma",
    version="0.1.0",
    author="Vaishali Swaminathan",
    author_email="vaishaliswaminathan@tamu.edu",
    description="PyMT plugin for NOAA-OWP Sac-SMA",
    url="https://github.com/NOAA-OWP/sac-sma",
    license="Apache-2.0",
    packages=find_packages(),
    include_package_data=True,
    install_requires=["numpy"],
    setup_requires=["cython"],
    ext_modules=ext_modules,
    cmdclass={"build_ext": build_ext},
    entry_points={"pymt.plugins": ["SAC_SMA=pymt_sac_sma.bmi:SAC_SMA"]},
    python_requires=">=3.10",
)
PYEOF

MANIFEST="${PKG_DIR}/MANIFEST.in"
{
  echo "recursive-include pymt_sac_sma *.pyx"
  echo "recursive-include pymt_sac_sma *.c"
  echo "recursive-include pymt_sac_sma *.f90"
  echo "recursive-include pymt_sac_sma *.h"
  echo "recursive-include pymt_sac_sma *.yaml"
} >> "${MANIFEST}"

echo
echo "Patched:"
echo "  - ${INTEROP_F90}"
echo "  - ${PKG_DIR}/pymt_sac_sma/__init__.py"
echo "  - ${PKG_DIR}/setup.py"
echo "  - ${MANIFEST}"
