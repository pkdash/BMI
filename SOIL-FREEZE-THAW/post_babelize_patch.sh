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

PYX_FILE="${PKG_DIR}/pymt_sft/lib/sft.pyx"

# ─── 1) Overwrite sft.pyx with the full, hand-written BMI implementation ─────
#
# The babelizer generates only the extern C++ class declaration and an empty
# SFT cdef class (just __cinit__/pass).  Every BMI method must be manually
# implemented so that Python can call them.  We overwrite the whole file here
# rather than patching the skeleton, because the skeleton changes too much
# between babelizer runs to make surgical sed/python fixes reliable.

cat > "${PYX_FILE}" <<'CYTHON_EOF'
# cython: c_string_type=str, c_string_encoding=ascii

import ctypes
from libcpp.string cimport string
from libcpp.vector cimport vector

cimport numpy as np
import numpy as np

# Mapping from C++ BMI type-name strings to numpy dtypes
DTYPE_MAP = {
    "double":           "float64",
    "float":            "float32",
    "int":              "int32",
    "long":             "int64",
    "unsigned int":     "uint32",
    "unsigned long":    "uint64",
}

# start: sft.pyx

cdef extern from "bmi_soil_freeze_thaw.hxx":
    cdef cppclass BmiSoilFreezeThaw:
        BmiSoilFreezeThaw() except +

        #  Model control functions.
        void Initialize(string config_file) except +
        void Update()
        void UpdateUntil(double time)
        void Finalize()

        #  Model information functions.
        string GetComponentName()
        int GetInputItemCount()
        int GetOutputItemCount()
        vector[string] GetInputVarNames()
        vector[string] GetOutputVarNames()

        #  Variable information functions
        int GetVarGrid(string name)
        string GetVarType(string name)
        string GetVarUnits(string name)
        int GetVarItemsize(string name)
        int GetVarNbytes(string name)
        string GetVarLocation(string name)

        double GetCurrentTime()
        double GetStartTime()
        double GetEndTime()
        string GetTimeUnits()
        double GetTimeStep()

        #  Variable getters
        void GetValue(string name, void *dest)
        void *GetValuePtr(string name)
        void GetValueAtIndices(string name, void *dest, int *inds, int count)

        #  Variable setters
        void SetValue(string name, void *src)
        void SetValueAtIndices(string name, int *inds, int count, void *src)

        #  Grid information functions
        int GetGridRank(const int grid)
        int GetGridSize(const int grid)
        string GetGridType(const int grid)

        void GetGridShape(const int grid, int *shape)
        void GetGridSpacing(const int grid, double *spacing)
        void GetGridOrigin(const int grid, double *origin)

        void GetGridX(const int grid, double *x)
        void GetGridY(const int grid, double *y)
        void GetGridZ(const int grid, double *z)

        int GetGridNodeCount(const int grid)
        int GetGridEdgeCount(const int grid)
        int GetGridFaceCount(const int grid)

        void GetGridEdgeNodes(const int grid, int *edge_nodes)
        void GetGridFaceEdges(const int grid, int *face_edges)
        void GetGridFaceNodes(const int grid, int *face_nodes)
        void GetGridNodesPerFace(const int grid, int *nodes_per_face)


cdef class SFT:
    cdef BmiSoilFreezeThaw _bmi

    METADATA = "../data/SFT"

    def __cinit__(self):
        pass

    # ------------------------------------------------------------------ #
    #  Model control                                                       #
    # ------------------------------------------------------------------ #

    def initialize(self, config_file):
        self._bmi.Initialize(config_file)

    def update(self):
        self._bmi.Update()

    def update_until(self, double time):
        self._bmi.UpdateUntil(time)

    def finalize(self):
        self._bmi.Finalize()

    # ------------------------------------------------------------------ #
    #  Model information                                                   #
    # ------------------------------------------------------------------ #

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

    # ------------------------------------------------------------------ #
    #  Variable information                                                #
    # ------------------------------------------------------------------ #

    def get_var_grid(self, name):
        return self._bmi.GetVarGrid(name)

    def get_var_type(self, name):
        return self._bmi.GetVarType(name)

    def get_var_units(self, name):
        return self._bmi.GetVarUnits(name)

    def get_var_itemsize(self, name):
        return self._bmi.GetVarItemsize(name)

    def get_var_nbytes(self, name):
        return self._bmi.GetVarNbytes(name)

    def get_var_location(self, name):
        return self._bmi.GetVarLocation(name)

    # ------------------------------------------------------------------ #
    #  Time information                                                    #
    # ------------------------------------------------------------------ #

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

    # ------------------------------------------------------------------ #
    #  Variable getters / setters                                          #
    # ------------------------------------------------------------------ #

    def get_value(self, name, np.ndarray dest):
        """Fill *dest* (pre-allocated numpy array) with the current values."""
        self._bmi.GetValue(name, <void *>dest.data)
        return dest

    def get_value_ptr(self, name):
        """Return a numpy array view directly into the model memory (no copy)."""
        cdef void *ptr
        ptr = self._bmi.GetValuePtr(name)

        var_type  = self.get_var_type(name)
        nbytes    = self.get_var_nbytes(name)
        itemsize  = self.get_var_itemsize(name)
        count     = nbytes // itemsize if itemsize > 0 else 0
        dtype_str = DTYPE_MAP.get(var_type, "float64")

        if dtype_str == "float64":
            return np.asarray(<np.float64_t[:count]>(<np.float64_t *>ptr))
        elif dtype_str == "float32":
            return np.asarray(<np.float32_t[:count]>(<np.float32_t *>ptr))
        elif dtype_str == "int32":
            return np.asarray(<np.int32_t[:count]>(<np.int32_t *>ptr))
        elif dtype_str == "int64":
            return np.asarray(<np.int64_t[:count]>(<np.int64_t *>ptr))
        else:
            return np.frombuffer(
                (<np.uint8_t[:nbytes]>(<np.uint8_t *>ptr)).base,
                dtype=np.dtype(dtype_str)
            )

    def get_value_at_indices(self, name, np.ndarray dest,
                              np.ndarray[int, ndim=1] inds):
        cdef int count = inds.shape[0]
        self._bmi.GetValueAtIndices(name, <void *>dest.data,
                                    <int *>inds.data, count)
        return dest

    def set_value(self, name, np.ndarray src):
        """Set model variable *name* from the numpy array *src*."""
        self._bmi.SetValue(name, <void *>src.data)

    def set_value_at_indices(self, name,
                              np.ndarray[int, ndim=1] inds,
                              np.ndarray src):
        cdef int count = inds.shape[0]
        self._bmi.SetValueAtIndices(name, <int *>inds.data, count,
                                    <void *>src.data)

    # ------------------------------------------------------------------ #
    #  Grid information                                                    #
    # ------------------------------------------------------------------ #

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

    def get_grid_edge_nodes(self, int grid,
                             np.ndarray[int, ndim=1] edge_nodes):
        self._bmi.GetGridEdgeNodes(grid, <int *>edge_nodes.data)
        return edge_nodes

    def get_grid_face_edges(self, int grid,
                             np.ndarray[int, ndim=1] face_edges):
        self._bmi.GetGridFaceEdges(grid, <int *>face_edges.data)
        return face_edges

    def get_grid_face_nodes(self, int grid,
                             np.ndarray[int, ndim=1] face_nodes):
        self._bmi.GetGridFaceNodes(grid, <int *>face_nodes.data)
        return face_nodes

    def get_grid_nodes_per_face(self, int grid,
                                 np.ndarray[int, ndim=1] nodes_per_face):
        self._bmi.GetGridNodesPerFace(grid, <int *>nodes_per_face.data)
        return nodes_per_face
CYTHON_EOF

echo "- Replaced sft.pyx with full BMI implementation"

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

common_flags = {
    "include_dirs": [np.get_include(), *include_dirs],
    "library_dirs": library_dirs,
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
    description="PyMT plugin for pymt_sft",
    long_description=long_description,
    version="0.1",
    url="https://github.com/pkdash/pymt_sft",
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
echo "Done. Patched:"
echo "  - ${PYX_FILE}  (full BMI implementation replacing babelizer skeleton)"
echo "  - ${PKG_DIR}/pymt_sft/__init__.py"
echo "  - ${PKG_DIR}/setup.py"
echo "  - ${PKG_DIR}/MANIFEST.in"
echo
echo "Next steps:"
echo "  cd ${PKG_DIR}"
echo "  rm -rf build dist *.egg-info"
echo "  uv build"
