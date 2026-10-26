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

PYX_FILE="${PKG_DIR}/pymt_smp/lib/smp.pyx"

cat > "${PYX_FILE}" <<'CYTHON_EOF'
# cython: c_string_type=str, c_string_encoding=ascii

from libcpp.string cimport string
from libcpp.vector cimport vector

cimport numpy as np
import numpy as np

DTYPE_MAP = {
    "double": "float64",
    "float": "float32",
    "int": "int32",
    "long": "int64",
    "long int": "int64",
    "unsigned int": "uint32",
    "unsigned long": "uint64",
    "unsigned long int": "uint64",
}

# start: smp.pyx

cdef extern from "bmi_soil_moisture_profile.hxx":
    cdef cppclass BmiSoilMoistureProfile:
        BmiSoilMoistureProfile() except +

        void Initialize(string config_file) except +
        void Update() except +
        void UpdateUntil(double time) except +
        void Finalize() except +

        string GetComponentName() except +
        int GetInputItemCount() except +
        int GetOutputItemCount() except +
        vector[string] GetInputVarNames() except +
        vector[string] GetOutputVarNames() except +

        int GetVarGrid(string name) except +
        string GetVarType(string name) except +
        string GetVarUnits(string name) except +
        int GetVarItemsize(string name) except +
        int GetVarNbytes(string name) except +
        string GetVarLocation(string name) except +

        double GetCurrentTime() except +
        double GetStartTime() except +
        double GetEndTime() except +
        string GetTimeUnits() except +
        double GetTimeStep() except +

        void GetValue(string name, void *dest) except +
        void *GetValuePtr(string name) except +
        void GetValueAtIndices(string name, void *dest, int *inds, int count) except +

        void SetValue(string name, void *src) except +
        void SetValueAtIndices(string name, int *inds, int count, void *src) except +

        int GetGridRank(const int grid) except +
        int GetGridSize(const int grid) except +
        string GetGridType(const int grid) except +
        void GetGridShape(const int grid, int *shape) except +
        void GetGridSpacing(const int grid, double *spacing) except +
        void GetGridOrigin(const int grid, double *origin) except +
        void GetGridX(const int grid, double *x) except +
        void GetGridY(const int grid, double *y) except +
        void GetGridZ(const int grid, double *z) except +
        int GetGridNodeCount(const int grid) except +
        int GetGridEdgeCount(const int grid) except +
        int GetGridFaceCount(const int grid) except +
        void GetGridEdgeNodes(const int grid, int *edge_nodes) except +
        void GetGridFaceEdges(const int grid, int *face_edges) except +
        void GetGridFaceNodes(const int grid, int *face_nodes) except +
        void GetGridNodesPerFace(const int grid, int *nodes_per_face) except +

        void ResetSize(string name) except +


cdef class SMP:
    cdef BmiSoilMoistureProfile _bmi

    METADATA = "../data/SMP"

    def __cinit__(self):
        pass

    def initialize(self, config_file):
        self._bmi.Initialize(config_file)

    def update(self):
        self._bmi.Update()

    def update_until(self, double time):
        self._bmi.UpdateUntil(time)

    def finalize(self):
        self._bmi.Finalize()

    def get_component_name(self):
        return self._bmi.GetComponentName()

    def get_input_item_count(self):
        return self._bmi.GetInputItemCount()

    def get_output_item_count(self):
        return self._bmi.GetOutputItemCount()

    def get_input_var_names(self):
        return tuple(self._bmi.GetInputVarNames())

    def get_output_var_names(self):
        return tuple(self._bmi.GetOutputVarNames())

    def get_var_grid(self, name):
        return self._bmi.GetVarGrid(name)

    def get_var_type(self, name):
        return DTYPE_MAP.get(self._bmi.GetVarType(name), self._bmi.GetVarType(name))

    def get_var_units(self, name):
        return self._bmi.GetVarUnits(name)

    def get_var_itemsize(self, name):
        return self._bmi.GetVarItemsize(name)

    def get_var_nbytes(self, name):
        return self._bmi.GetVarNbytes(name)

    def get_var_location(self, name):
        return self._bmi.GetVarLocation(name)

    def get_current_time(self):
        return self._bmi.GetCurrentTime()

    def get_start_time(self):
        return self._bmi.GetStartTime()

    def get_end_time(self):
        return self._bmi.GetEndTime()

    def get_time_units(self):
        return self._bmi.GetTimeUnits()

    def get_time_step(self):
        return self._bmi.GetTimeStep()

    def get_value(self, name, np.ndarray dest):
        self._bmi.GetValue(name, <void *>dest.data)
        return dest

    def get_value_ptr(self, name):
        cdef void *ptr
        ptr = self._bmi.GetValuePtr(name)

        var_type = self._bmi.GetVarType(name)
        nbytes = self.get_var_nbytes(name)
        itemsize = self.get_var_itemsize(name)
        count = nbytes // itemsize if itemsize > 0 else 0
        dtype_str = DTYPE_MAP.get(var_type, "float64")

        if dtype_str == "float64":
            return np.asarray(<np.float64_t[:count]>(<np.float64_t *>ptr))
        elif dtype_str == "float32":
            return np.asarray(<np.float32_t[:count]>(<np.float32_t *>ptr))
        elif dtype_str == "int32":
            return np.asarray(<np.int32_t[:count]>(<np.int32_t *>ptr))
        elif dtype_str == "int64":
            return np.asarray(<np.int64_t[:count]>(<np.int64_t *>ptr))
        elif dtype_str == "uint32":
            return np.asarray(<np.uint32_t[:count]>(<np.uint32_t *>ptr))
        elif dtype_str == "uint64":
            return np.asarray(<np.uint64_t[:count]>(<np.uint64_t *>ptr))
        else:
            return np.frombuffer(
                (<np.uint8_t[:nbytes]>(<np.uint8_t *>ptr)).base,
                dtype=np.dtype(dtype_str),
            )

    def get_value_at_indices(self, name, np.ndarray dest,
                             np.ndarray[int, ndim=1] inds):
        cdef int count = inds.shape[0]
        self._bmi.GetValueAtIndices(name, <void *>dest.data,
                                    <int *>inds.data, count)
        return dest

    def set_value(self, name, np.ndarray src):
        if not src.flags["C_CONTIGUOUS"]:
            src = np.ascontiguousarray(src)
        self._bmi.SetValue(name, <void *>src.data)

    def set_value_at_indices(self, name,
                             np.ndarray[int, ndim=1] inds,
                             np.ndarray src):
        cdef int count = inds.shape[0]
        if not src.flags["C_CONTIGUOUS"]:
            src = np.ascontiguousarray(src)
        self._bmi.SetValueAtIndices(name, <int *>inds.data, count,
                                    <void *>src.data)

    def get_grid_rank(self, int grid):
        return self._bmi.GetGridRank(grid)

    def get_grid_size(self, int grid):
        return self._bmi.GetGridSize(grid)

    def get_grid_type(self, int grid):
        return self._bmi.GetGridType(grid)

    def get_grid_shape(self, int grid, np.ndarray[int, ndim=1] shape):
        self._bmi.GetGridShape(grid, <int *>shape.data)
        return shape

    def get_grid_spacing(self, int grid, np.ndarray[double, ndim=1] spacing):
        self._bmi.GetGridSpacing(grid, <double *>spacing.data)
        return spacing

    def get_grid_origin(self, int grid, np.ndarray[double, ndim=1] origin):
        self._bmi.GetGridOrigin(grid, <double *>origin.data)
        return origin

    def get_grid_x(self, int grid, np.ndarray[double, ndim=1] x):
        self._bmi.GetGridX(grid, <double *>x.data)
        return x

    def get_grid_y(self, int grid, np.ndarray[double, ndim=1] y):
        self._bmi.GetGridY(grid, <double *>y.data)
        return y

    def get_grid_z(self, int grid, np.ndarray[double, ndim=1] z):
        self._bmi.GetGridZ(grid, <double *>z.data)
        return z

    def get_grid_node_count(self, int grid):
        return self._bmi.GetGridNodeCount(grid)

    def get_grid_edge_count(self, int grid):
        return self._bmi.GetGridEdgeCount(grid)

    def get_grid_face_count(self, int grid):
        return self._bmi.GetGridFaceCount(grid)

    def get_grid_edge_nodes(self, int grid, np.ndarray[int, ndim=1] edge_nodes):
        self._bmi.GetGridEdgeNodes(grid, <int *>edge_nodes.data)
        return edge_nodes

    def get_grid_face_edges(self, int grid, np.ndarray[int, ndim=1] face_edges):
        self._bmi.GetGridFaceEdges(grid, <int *>face_edges.data)
        return face_edges

    def get_grid_face_nodes(self, int grid, np.ndarray[int, ndim=1] face_nodes):
        self._bmi.GetGridFaceNodes(grid, <int *>face_nodes.data)
        return face_nodes

    def get_grid_nodes_per_face(self, int grid,
                                np.ndarray[int, ndim=1] nodes_per_face):
        self._bmi.GetGridNodesPerFace(grid, <int *>nodes_per_face.data)
        return nodes_per_face

    def reset_size(self, name):
        self._bmi.ResetSize(name)
CYTHON_EOF

echo "- Replaced smp.pyx with full BMI implementation"

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
echo "  - ${PYX_FILE}"
echo "  - ${PKG_DIR}/pymt_smp/__init__.py"
echo "  - ${PKG_DIR}/setup.py"
echo "  - ${PKG_DIR}/MANIFEST.in"
echo
echo "Next steps:"
echo "  cd ${PKG_DIR}"
echo "  rm -rf build dist *.egg-info"
echo "  uv build"
