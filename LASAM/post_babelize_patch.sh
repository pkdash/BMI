#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_lasam"
# Install the generated BMI wrapper (.pyx + NumPy helpers) rendered by
# ../common/render_wrappers.py and vendored in ./wrapper; see ../common/README.md.
bash "${ROOT_DIR}/wrapper/install.sh" "${PKG_DIR}"

cat > "${PKG_DIR}/pymt_lasam/__init__.py" <<'PY'
from importlib.metadata import PackageNotFoundError, version
try:
    __version__ = version("pymt_lasam")
except PackageNotFoundError:
    __version__ = "0+unknown"
from .bmi import LASAM
__all__ = ["LASAM"]
PY

cat > "${PKG_DIR}/setup.py" <<'PY'
import os, sys
from pathlib import Path
import numpy as np
from setuptools import Extension, find_packages, setup
try:
    from Cython.Build import cythonize
except ImportError:
    cythonize = None

def existing(items):
    out=[]
    for p in items:
        if p and Path(p).exists() and p not in out: out.append(p)
    return out
root=os.environ.get("LASAM_ROOT", "")
include_dirs=existing([os.environ.get("LASAM_INCLUDE_DIR", ""), os.environ.get("LASAM_BMI_DIR", ""), f"{root}/include" if root else "", f"{root}/bmi" if root else "", f"{root}/giuh" if root else "", "/workspace/LGAR-C/include", "/workspace/LGAR-C/bmi", "/workspace/LGAR-C/giuh", f"{sys.prefix}/include"])
library_dirs=existing([os.environ.get("LASAM_LIB_DIR", ""), f"{root}/build" if root else "", f"{root}/cmake_build" if root else "", "/workspace/LGAR-C/build", f"{sys.prefix}/lib"])
pyx=Path("pymt_lasam/lib/lasam.pyx"); cpp=Path("pymt_lasam/lib/lasam.cpp")
source=str(pyx if cythonize is not None and pyx.exists() else cpp)
kwargs=dict(sources=[source], include_dirs=[np.get_include(), *include_dirs], library_dirs=library_dirs, libraries=["lasambmi", "m"], language="c++", extra_compile_args=["-std=c++14"])
rpath=os.environ.get("LASAM_RPATH") or os.environ.get("LASAM_LIB_DIR")
if rpath and Path(rpath).exists() and sys.platform.startswith("linux"): kwargs["runtime_library_dirs"]=[rpath]
ext=[Extension("pymt_lasam.lib.lasam", **kwargs)]
if cythonize is not None and source.endswith(".pyx"): ext=cythonize(ext, language_level=3)
setup(name="pymt_lasam", version="0.1.0", author="Vaishali Swaminathan", author_email="vaishaliswaminathan@tamu.edu", description="PyMT plugin for NOAA-OWP LASAM", url="https://github.com/NOAA-OWP/LGAR-C", project_urls={"Source": "https://github.com/pkdash/BMI/tree/main/LASAM/pymt_lasam"}, license="Apache-2.0", packages=find_packages(), include_package_data=True, install_requires=["numpy"], ext_modules=ext, entry_points={"pymt.plugins":["LASAM=pymt_lasam.bmi:LASAM"]}, python_requires=">=3.10")
PY

sed -i 's/recursive-exclude pymt_lasam \*\.cpp/recursive-include pymt_lasam *.cpp/' "${PKG_DIR}/MANIFEST.in" 2>/dev/null || true

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
