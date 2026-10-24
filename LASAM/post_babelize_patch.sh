#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_lasam"
PYX_FILE="${PKG_DIR}/pymt_lasam/lib/lasam.pyx"
mkdir -p "$(dirname "$PYX_FILE")"
cat > "$PYX_FILE" <<'CYTHON'
# cython: c_string_type=str, c_string_encoding=utf8
from libcpp.string cimport string
from libcpp.vector cimport vector
cimport numpy as np
import numpy as np

DTYPE_MAP = {"double":"float64", "float":"float32", "int":"int32", "long":"int64", "long int":"int64", "unsigned int":"uint32", "unsigned long":"uint64"}

cdef extern from "bmi_lgar.hxx":
    cdef cppclass BmiLGAR:
        BmiLGAR() except +
        void Initialize(string) except +
        void Update() except +
        void UpdateUntil(double) except +
        void Finalize() except +
        string GetComponentName() except +
        int GetInputItemCount() except +
        int GetOutputItemCount() except +
        vector[string] GetInputVarNames() except +
        vector[string] GetOutputVarNames() except +
        int GetVarGrid(string) except +
        string GetVarType(string) except +
        int GetVarItemsize(string) except +
        string GetVarUnits(string) except +
        int GetVarNbytes(string) except +
        string GetVarLocation(string) except +
        double GetCurrentTime() except +
        double GetStartTime() except +
        double GetEndTime() except +
        string GetTimeUnits() except +
        double GetTimeStep() except +
        void GetValue(string, void*) except +
        void* GetValuePtr(string) except +
        void GetValueAtIndices(string, void*, int*, int) except +
        void SetValue(string, void*) except +
        void SetValueAtIndices(string, int*, int, void*) except +
        int GetGridRank(int) except +
        int GetGridSize(int) except +
        string GetGridType(int) except +
        void GetGridShape(int, int*) except +
        void GetGridSpacing(int, double*) except +
        void GetGridOrigin(int, double*) except +
        void GetGridX(int, double*) except +
        void GetGridY(int, double*) except +
        void GetGridZ(int, double*) except +
        int GetGridNodeCount(int) except +
        int GetGridEdgeCount(int) except +
        int GetGridFaceCount(int) except +
        void GetGridEdgeNodes(int, int*) except +
        void GetGridFaceEdges(int, int*) except +
        void GetGridFaceNodes(int, int*) except +
        void GetGridNodesPerFace(int, int*) except +

cdef class LASAM:
    cdef BmiLGAR _bmi
    METADATA = "../data/LASAM"
    def initialize(self, config_file): self._bmi.Initialize(config_file)
    def update(self): self._bmi.Update()
    def update_until(self, double time): self._bmi.UpdateUntil(time)
    def finalize(self): self._bmi.Finalize()
    def get_component_name(self): return self._bmi.GetComponentName()
    def get_input_item_count(self): return self._bmi.GetInputItemCount()
    def get_output_item_count(self): return self._bmi.GetOutputItemCount()
    def get_input_var_names(self): return tuple(self._bmi.GetInputVarNames())
    def get_output_var_names(self): return tuple(self._bmi.GetOutputVarNames())
    def get_var_grid(self, name): return self._bmi.GetVarGrid(name)
    def get_var_type(self, name): return DTYPE_MAP.get(self._bmi.GetVarType(name), self._bmi.GetVarType(name))
    def get_var_itemsize(self, name): return self._bmi.GetVarItemsize(name)
    def get_var_units(self, name): return self._bmi.GetVarUnits(name)
    def get_var_nbytes(self, name): return self._bmi.GetVarNbytes(name)
    def get_var_location(self, name): return self._bmi.GetVarLocation(name)
    def get_current_time(self): return self._bmi.GetCurrentTime()
    def get_start_time(self): return self._bmi.GetStartTime()
    def get_end_time(self): return self._bmi.GetEndTime()
    def get_time_units(self): return self._bmi.GetTimeUnits()
    def get_time_step(self): return self._bmi.GetTimeStep()
    def get_value(self, name, np.ndarray dest):
        self._bmi.GetValue(name, <void*>dest.data); return dest
    def get_value_ptr(self, name):
        cdef void* ptr = self._bmi.GetValuePtr(name)
        cdef int nbytes = self._bmi.GetVarNbytes(name)
        cdef int itemsize = self._bmi.GetVarItemsize(name)
        cdef Py_ssize_t count = nbytes // itemsize if itemsize > 0 else 0
        c_type = self._bmi.GetVarType(name)
        dtype_str = DTYPE_MAP.get(c_type, "float64")
        if ptr == NULL: raise RuntimeError(f"LASAM returned null pointer for {name!r}")
        if dtype_str == "float64": return np.asarray(<np.float64_t[:count]>(<np.float64_t*>ptr))
        if dtype_str == "float32": return np.asarray(<np.float32_t[:count]>(<np.float32_t*>ptr))
        if dtype_str == "int32": return np.asarray(<np.int32_t[:count]>(<np.int32_t*>ptr))
        if dtype_str == "int64": return np.asarray(<np.int64_t[:count]>(<np.int64_t*>ptr))
        if dtype_str == "uint32": return np.asarray(<np.uint32_t[:count]>(<np.uint32_t*>ptr))
        if dtype_str == "uint64": return np.asarray(<np.uint64_t[:count]>(<np.uint64_t*>ptr))
        raise TypeError(f"Unsupported LASAM BMI type: {c_type!r}")
    def get_value_at_indices(self, name, np.ndarray dest, np.ndarray[np.int32_t, ndim=1, mode="c"] inds):
        self._bmi.GetValueAtIndices(name, <void*>dest.data, <int*>inds.data, inds.shape[0]); return dest
    def set_value(self, name, np.ndarray src):
        if not src.flags["C_CONTIGUOUS"]: src = np.ascontiguousarray(src)
        self._bmi.SetValue(name, <void*>src.data)
    def set_value_at_indices(self, name, np.ndarray[np.int32_t, ndim=1, mode="c"] inds, np.ndarray src):
        if not src.flags["C_CONTIGUOUS"]: src = np.ascontiguousarray(src)
        self._bmi.SetValueAtIndices(name, <int*>inds.data, inds.shape[0], <void*>src.data)
    def get_grid_rank(self, int grid): return self._bmi.GetGridRank(grid)
    def get_grid_size(self, int grid): return self._bmi.GetGridSize(grid)
    def get_grid_type(self, int grid): return self._bmi.GetGridType(grid)
    def get_grid_shape(self, int grid, np.ndarray[np.int32_t, ndim=1, mode="c"] a): self._bmi.GetGridShape(grid, <int*>a.data); return a
    def get_grid_spacing(self, int grid, np.ndarray[np.float64_t, ndim=1, mode="c"] a): self._bmi.GetGridSpacing(grid, <double*>a.data); return a
    def get_grid_origin(self, int grid, np.ndarray[np.float64_t, ndim=1, mode="c"] a): self._bmi.GetGridOrigin(grid, <double*>a.data); return a
    def get_grid_x(self, int grid, np.ndarray[np.float64_t, ndim=1, mode="c"] a): self._bmi.GetGridX(grid, <double*>a.data); return a
    def get_grid_y(self, int grid, np.ndarray[np.float64_t, ndim=1, mode="c"] a): self._bmi.GetGridY(grid, <double*>a.data); return a
    def get_grid_z(self, int grid, np.ndarray[np.float64_t, ndim=1, mode="c"] a): self._bmi.GetGridZ(grid, <double*>a.data); return a
    def get_grid_node_count(self, int grid): return self._bmi.GetGridNodeCount(grid)
    def get_grid_edge_count(self, int grid): return self._bmi.GetGridEdgeCount(grid)
    def get_grid_face_count(self, int grid): return self._bmi.GetGridFaceCount(grid)
    def get_grid_edge_nodes(self, int grid, np.ndarray[np.int32_t, ndim=1, mode="c"] a): self._bmi.GetGridEdgeNodes(grid, <int*>a.data); return a
    def get_grid_face_edges(self, int grid, np.ndarray[np.int32_t, ndim=1, mode="c"] a): self._bmi.GetGridFaceEdges(grid, <int*>a.data); return a
    def get_grid_face_nodes(self, int grid, np.ndarray[np.int32_t, ndim=1, mode="c"] a): self._bmi.GetGridFaceNodes(grid, <int*>a.data); return a
    def get_grid_nodes_per_face(self, int grid, np.ndarray[np.int32_t, ndim=1, mode="c"] a): self._bmi.GetGridNodesPerFace(grid, <int*>a.data); return a
CYTHON

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
setup(name="pymt_lasam", version="0.1.0", author="Vaishali Swaminathan", author_email="vaishaliswaminathan@tamu.edu", description="PyMT plugin for LASAM/CASAM", url="https://github.com/NOAA-OWP/LGAR-C", license="Apache-2.0", packages=find_packages(), include_package_data=True, install_requires=["numpy"], ext_modules=ext, entry_points={"pymt.plugins":["LASAM=pymt_lasam.bmi:LASAM"]}, python_requires=">=3.10")
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
