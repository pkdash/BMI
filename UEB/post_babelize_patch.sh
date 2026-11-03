#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_ueb"
PYX_FILE="${PKG_DIR}/pymt_ueb/lib/ueb.pyx"

[[ -d "${PKG_DIR}" ]] || { echo "ERROR: ${PKG_DIR} not found" >&2; exit 1; }

mkdir -p "$(dirname "${PYX_FILE}")"

cat > "${PYX_FILE}" <<'CYTHON_EOF'
# cython: c_string_type=str, c_string_encoding=utf8

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
    "char": "int8",
    "unsigned char": "uint8",
    "uint64_t": "uint64",
}

cdef extern from "bmi_ueb.hxx" namespace "ueb":
    cdef cppclass BmiUEB:
        BmiUEB() except +

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
        int GetVarItemsize(string name) except +
        string GetVarUnits(string name) except +
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

        int GetGridRank(int grid) except +
        int GetGridSize(int grid) except +
        string GetGridType(int grid) except +
        void GetGridShape(int grid, int *shape) except +
        void GetGridSpacing(int grid, double *spacing) except +
        void GetGridOrigin(int grid, double *origin) except +
        void GetGridX(int grid, double *x) except +
        void GetGridY(int grid, double *y) except +
        void GetGridZ(int grid, double *z) except +
        int GetGridNodeCount(int grid) except +
        int GetGridEdgeCount(int grid) except +
        int GetGridFaceCount(int grid) except +
        void GetGridEdgeNodes(int grid, int *edge_nodes) except +
        void GetGridFaceEdges(int grid, int *face_edges) except +
        void GetGridFaceNodes(int grid, int *face_nodes) except +
        void GetGridNodesPerFace(int grid, int *nodes_per_face) except +

        void GetStartTimeInGregorianCalendar(int& y, int& m, int& d, int& h) except +
        void GetEndTimeInGregorianCalendar(int& y, int& m, int& d, int& h) except +
        void GetCurrentTimeInGregorianCalendar(int& y, int& m, int& d, int& h) except +


cdef class UEB:
    cdef BmiUEB _bmi

    METADATA = "../data/UEB"

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

    def get_var_itemsize(self, name):
        return self._bmi.GetVarItemsize(name)

    def get_var_units(self, name):
        return self._bmi.GetVarUnits(name)

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
        cdef void *ptr = self._bmi.GetValuePtr(name)
        cdef int nbytes = self._bmi.GetVarNbytes(name)
        cdef int itemsize = self._bmi.GetVarItemsize(name)
        cdef Py_ssize_t count = nbytes // itemsize if itemsize > 0 else 0

        c_type = self._bmi.GetVarType(name)
        dtype_str = DTYPE_MAP.get(c_type, "float64")

        if ptr == NULL:
            raise RuntimeError(f"UEB returned a null pointer for variable {name!r}")

        if dtype_str == "float64":
            return np.asarray(<np.float64_t[:count]>(<np.float64_t *>ptr))
        elif dtype_str == "float32":
            return np.asarray(<np.float32_t[:count]>(<np.float32_t *>ptr))
        elif dtype_str == "int32":
            return np.asarray(<np.int32_t[:count]>(<np.int32_t *>ptr))
        elif dtype_str == "int64":
            return np.asarray(<np.int64_t[:count]>(<np.int64_t *>ptr))
        elif dtype_str == "uint64":
            return np.asarray(<np.uint64_t[:count]>(<np.uint64_t *>ptr))
        elif dtype_str == "uint32":
            return np.asarray(<np.uint32_t[:count]>(<np.uint32_t *>ptr))
        elif dtype_str == "uint8":
            return np.asarray(<np.uint8_t[:count]>(<np.uint8_t *>ptr))
        elif dtype_str == "int8":
            return np.asarray(<np.int8_t[:count]>(<np.int8_t *>ptr))
        raise TypeError(f"Unsupported UEB BMI type: {c_type!r}")

    def get_value_at_indices(self, name, np.ndarray dest,
                             np.ndarray[np.int32_t, ndim=1, mode="c"] inds):
        self._bmi.GetValueAtIndices(
            name, <void *>dest.data, <int *>inds.data, inds.shape[0]
        )
        return dest

    def set_value(self, name, np.ndarray src):
        if not src.flags["C_CONTIGUOUS"]:
            src = np.ascontiguousarray(src)
        self._bmi.SetValue(name, <void *>src.data)

    def set_value_at_indices(self, name,
                             np.ndarray[np.int32_t, ndim=1, mode="c"] inds,
                             np.ndarray src):
        if not src.flags["C_CONTIGUOUS"]:
            src = np.ascontiguousarray(src)
        self._bmi.SetValueAtIndices(
            name, <int *>inds.data, inds.shape[0], <void *>src.data
        )

    def get_grid_rank(self, int grid):
        return self._bmi.GetGridRank(grid)

    def get_grid_size(self, int grid):
        return self._bmi.GetGridSize(grid)

    def get_grid_type(self, int grid):
        return self._bmi.GetGridType(grid)

    def get_grid_shape(self, int grid,
                       np.ndarray[np.int32_t, ndim=1, mode="c"] shape):
        self._bmi.GetGridShape(grid, <int *>shape.data)
        return shape

    def get_grid_spacing(self, int grid,
                         np.ndarray[np.float64_t, ndim=1, mode="c"] spacing):
        self._bmi.GetGridSpacing(grid, <double *>spacing.data)
        return spacing

    def get_grid_origin(self, int grid,
                        np.ndarray[np.float64_t, ndim=1, mode="c"] origin):
        self._bmi.GetGridOrigin(grid, <double *>origin.data)
        return origin

    def get_grid_x(self, int grid,
                   np.ndarray[np.float64_t, ndim=1, mode="c"] x):
        self._bmi.GetGridX(grid, <double *>x.data)
        return x

    def get_grid_y(self, int grid,
                   np.ndarray[np.float64_t, ndim=1, mode="c"] y):
        self._bmi.GetGridY(grid, <double *>y.data)
        return y

    def get_grid_z(self, int grid,
                   np.ndarray[np.float64_t, ndim=1, mode="c"] z):
        self._bmi.GetGridZ(grid, <double *>z.data)
        return z

    def get_grid_node_count(self, int grid):
        return self._bmi.GetGridNodeCount(grid)

    def get_grid_edge_count(self, int grid):
        return self._bmi.GetGridEdgeCount(grid)

    def get_grid_face_count(self, int grid):
        return self._bmi.GetGridFaceCount(grid)

    def get_grid_edge_nodes(self, int grid,
                            np.ndarray[np.int32_t, ndim=1, mode="c"] values):
        self._bmi.GetGridEdgeNodes(grid, <int *>values.data)
        return values

    def get_grid_face_edges(self, int grid,
                            np.ndarray[np.int32_t, ndim=1, mode="c"] values):
        self._bmi.GetGridFaceEdges(grid, <int *>values.data)
        return values

    def get_grid_face_nodes(self, int grid,
                            np.ndarray[np.int32_t, ndim=1, mode="c"] values):
        self._bmi.GetGridFaceNodes(grid, <int *>values.data)
        return values

    def get_grid_nodes_per_face(self, int grid,
                                np.ndarray[np.int32_t, ndim=1, mode="c"] values):
        self._bmi.GetGridNodesPerFace(grid, <int *>values.data)
        return values

    def get_start_time_gregorian(self):
        cdef int y, m, d, h
        self._bmi.GetStartTimeInGregorianCalendar(y, m, d, h)
        return y, m, d, h

    def get_end_time_gregorian(self):
        cdef int y, m, d, h
        self._bmi.GetEndTimeInGregorianCalendar(y, m, d, h)
        return y, m, d, h

    def get_current_time_gregorian(self):
        cdef int y, m, d, h
        self._bmi.GetCurrentTimeInGregorianCalendar(y, m, d, h)
        return y, m, d, h
CYTHON_EOF

cat > "${PKG_DIR}/pymt_ueb/__init__.py" <<'PYEOF'
from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("pymt_ueb")
except PackageNotFoundError:
    __version__ = "0+unknown"

from .bmi import UEB

__all__ = ["UEB"]
PYEOF

cat > "${PKG_DIR}/setup.py" <<'PYEOF'
#!/usr/bin/env python
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


def unique_existing(paths):
    result, seen = [], set()
    for path in paths:
        if not path:
            continue
        path = str(Path(path).expanduser())
        if path not in seen and Path(path).exists():
            seen.add(path)
            result.append(path)
    return result


def pkg_config_dirs(package_names=("uebcxx", "bmiuebcxx")):
    includes, libraries = [], []
    for package in package_names:
        try:
            out = subprocess.check_output(
                ["pkg-config", "--cflags", package],
                text=True, stderr=subprocess.DEVNULL
            )
            includes.extend(
                token[2:] for token in shlex.split(out)
                if token.startswith("-I") and len(token) > 2
            )
        except Exception:
            pass
        try:
            out = subprocess.check_output(
                ["pkg-config", "--libs-only-L", package],
                text=True, stderr=subprocess.DEVNULL
            )
            libraries.extend(
                token[2:] for token in shlex.split(out)
                if token.startswith("-L") and len(token) > 2
            )
        except Exception:
            pass
    return includes, libraries


def discover_ueb_paths():
    env = os.environ
    root = env.get("UEB_ROOT", "")
    conda = env.get("CONDA_PREFIX", "")
    pkg_inc, pkg_lib = pkg_config_dirs()

    include_candidates = [
        env.get("UEB_INCLUDE_DIR", ""),
        env.get("BMICXX_INCLUDE_DIRS", ""),
        f"{root}/src/bmi" if root else "",
        f"{root}/src/ueb" if root else "",
        f"{root}/src/utilities" if root else "",
        f"{Path(root).parent}/bmi-cxx" if root else "",
        "/workspace/ueb_bmi/src/bmi",
        "/workspace/ueb_bmi/src/ueb",
        "/workspace/ueb_bmi/src/utilities",
        "/workspace/bmi-cxx",
        f"{sys.prefix}/include",
        f"{conda}/include" if conda else "",
    ] + pkg_inc

    library_candidates = [
        env.get("UEB_LIB_DIR", ""),
        f"{root}/cmake_build/src" if root else "",
        f"{root}/build/src" if root else "",
        f"{root}/cmake_build" if root else "",
        "/workspace/ueb_bmi/cmake_build/src",
        f"{sys.prefix}/lib",
        f"{conda}/lib" if conda else "",
    ] + pkg_lib

    return unique_existing(include_candidates), unique_existing(library_candidates)


include_dirs, library_dirs = discover_ueb_paths()
rpath = os.environ.get("UEB_RPATH") or os.environ.get("UEB_LIB_DIR")

pyx = Path("pymt_ueb/lib/ueb.pyx")
cpp = Path("pymt_ueb/lib/ueb.cpp")
if cythonize is not None and pyx.exists():
    source = str(pyx)
elif cpp.exists():
    source = str(cpp)
else:
    raise RuntimeError("Missing pymt_ueb/lib/ueb.pyx and generated ueb.cpp")

extension_kwargs = dict(
    sources=[source],
    include_dirs=[np.get_include(), *include_dirs],
    library_dirs=library_dirs,
    libraries=["bmiuebcxx", "netcdf", "boost_serialization"],
    language="c++",
    extra_compile_args=["-std=c++17"],
)
if rpath and Path(rpath).exists() and sys.platform.startswith("linux"):
    extension_kwargs["runtime_library_dirs"] = [rpath]

ext_modules = [Extension("pymt_ueb.lib.ueb", **extension_kwargs)]
if cythonize is not None and source.endswith(".pyx"):
    ext_modules = cythonize(ext_modules, language_level=3)

setup(
    name="pymt_ueb",
    version="0.1.0",
    author="Vaishali Swaminathan",
    author_email="vaishaliswaminathan@tamu.edu",
    description="PyMT plugin for NGWPC UEB",
    url="https://github.com/NGWPC/ueb_bmi",
    project_urls={
        "Source": "https://github.com/pkdash/BMI/tree/main/UEB/pymt_ueb",
    },
    license="MIT",
    packages=find_packages(),
    include_package_data=True,
    install_requires=["numpy"],
    setup_requires=["cython"],
    ext_modules=ext_modules,
    entry_points={"pymt.plugins": ["UEB=pymt_ueb.bmi:UEB"]},
    python_requires=">=3.10",
)
PYEOF

if [[ -f "${PKG_DIR}/MANIFEST.in" ]]; then
  sed -i 's/recursive-exclude pymt_ueb \*\.cpp/recursive-include pymt_ueb *.cpp/' \
    "${PKG_DIR}/MANIFEST.in"
fi

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

echo "Patched pymt_ueb for ueb::BmiUEB."
