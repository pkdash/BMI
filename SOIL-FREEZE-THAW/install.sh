#!/usr/bin/env bash
set -euo pipefail

# Install pymt_sft from a local sdist tarball into the CURRENT active conda env.
#
# Assumptions:
#   - This script and pymt_sft-*.tar.gz are in the same directory.
#   - libsftbmi.so is either pre-built or the SoilFreezeThaw source tree is
#     accessible (cmake + a C++ compiler must be available to rebuild it).
#
# If libsftbmi.so was built with -fvisibility=hidden (conda-forge compiler
# default) the BmiSoilFreezeThaw vtable will not be exported, causing
#   ImportError: undefined symbol: _ZTV17BmiSoilFreezeThaw
# This script detects that case and rebuilds the library with
# -DCMAKE_CXX_VISIBILITY_PRESET=default before installing the Python wrapper.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${CONDA_PREFIX:-}" ]]; then
  echo "ERROR: No active conda environment detected (CONDA_PREFIX is empty)." >&2
  echo "Activate your target env first, then run this script." >&2
  exit 1
fi

PYTHON_BIN="${CONDA_PREFIX}/bin/python"
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "ERROR: Active conda env does not contain an executable Python: ${PYTHON_BIN}" >&2
  exit 1
fi

if ! "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
  echo "ERROR: pip is not available in the active conda env." >&2
  exit 1
fi

# Prefer newest tarball if multiple are present.
mapfile -t TARBALLS < <(ls -1t "${SCRIPT_DIR}"/pymt_sft-*.tar.gz 2>/dev/null || true)
if [[ ${#TARBALLS[@]} -eq 0 ]]; then
  echo "ERROR: No pymt_sft-*.tar.gz found in ${SCRIPT_DIR}" >&2
  exit 1
fi
TARBALL="${TARBALLS[0]}"

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Returns true if libsftbmi.so exports the BmiSoilFreezeThaw vtable.
_vtable_exported() {
  local lib="$1"
  have_cmd nm && nm -D "$lib" 2>/dev/null | grep -q '_ZTV17BmiSoilFreezeThaw'
}

# ─── Locate libsftbmi.so ──────────────────────────────────────────────────────

pkg_config_include_dirs() {
  if have_cmd pkg-config && pkg-config --exists sftbmi 2>/dev/null; then
    pkg-config --cflags sftbmi 2>/dev/null | tr ' ' '\n' | sed -n 's/^-I//p'
  fi
}

pkg_config_library_dirs() {
  if have_cmd pkg-config && pkg-config --exists sftbmi 2>/dev/null; then
    pkg-config --libs-only-L sftbmi 2>/dev/null | tr ' ' '\n' | sed -n 's/^-L//p'
  fi
}

first_existing_libdir() {
  local d
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    if compgen -G "$d/libsftbmi.so*" > /dev/null; then
      echo "$d"; return 0
    fi
  done
  return 1
}

SFT_LIB_DIR="${SFT_LIB_DIR:-}"

# 1) User-set env var.
if [[ -n "$SFT_LIB_DIR" ]] && compgen -G "$SFT_LIB_DIR/libsftbmi.so*" > /dev/null 2>&1; then
  : # already good
else
  # 2) pkg-config
  if SFT_LIB_DIR="$(pkg_config_library_dirs | first_existing_libdir 2>/dev/null || true)"; then
    :
  fi
fi

# 3) Search known roots
if [[ -z "$SFT_LIB_DIR" ]]; then
  SEARCH_ROOTS=(
    "/workspace/sft/build"
    "/workspace/sft"
    "/opt"
    "/usr/local"
    "/usr"
    "$HOME"
  )
  for root in "${SEARCH_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    hit="$(find "$root" -type f \
      \( -name 'libsftbmi.so' -o -name 'libsftbmi.so.*' \) \
      2>/dev/null | head -n1 || true)"
    if [[ -n "$hit" ]]; then
      SFT_LIB_DIR="$(dirname "$hit")"
      break
    fi
  done
fi

if [[ -z "$SFT_LIB_DIR" ]]; then
  echo "ERROR: Could not locate libsftbmi.so* on this system." >&2
  echo "Set SFT_LIB_DIR to the directory containing libsftbmi.so and re-run:" >&2
  echo "  export SFT_LIB_DIR=/path/to/sft/build" >&2
  echo "  ./install.sh" >&2
  exit 1
fi

# ─── Locate SFT_ROOT (for headers) ───────────────────────────────────────────

SFT_ROOT="${SFT_ROOT:-}"

if [[ -z "$SFT_ROOT" ]]; then
  for candidate in \
    "$(cd "$SFT_LIB_DIR/.."   && pwd 2>/dev/null || true)" \
    "$(cd "$SFT_LIB_DIR/../.." && pwd 2>/dev/null || true)"; do
    [[ -n "$candidate" ]] || continue
    if [[ -f "$candidate/include/bmi_soil_freeze_thaw.hxx" ]]; then
      SFT_ROOT="$candidate"; break
    fi
  done
fi

if [[ -z "$SFT_ROOT" || ! -f "$SFT_ROOT/include/bmi_soil_freeze_thaw.hxx" ]]; then
  echo "ERROR: Could not determine SFT_ROOT containing include/bmi_soil_freeze_thaw.hxx" >&2
  echo "Set SFT_ROOT manually and re-run:" >&2
  echo "  export SFT_ROOT=/path/to/SoilFreezeThaw" >&2
  echo "  ./install.sh" >&2
  exit 1
fi

# ─── Verify vtable visibility; rebuild libsftbmi.so if needed ────────────────

# Find the actual .so file (prefer the unversioned symlink).
_LIBSFT=""
for _f in "${SFT_LIB_DIR}/libsftbmi.so" "${SFT_LIB_DIR}/libsftbmi.so."*; do
  [[ -f "$_f" ]] && { _LIBSFT="$_f"; break; }
done

if [[ -n "$_LIBSFT" ]] && ! _vtable_exported "$_LIBSFT"; then
  echo
  echo "WARNING: ${_LIBSFT} does NOT export the BmiSoilFreezeThaw vtable."
  echo "  This is typically caused by building with -fvisibility=hidden"
  echo "  (the conda-forge compiler default).  Without the vtable export,"
  echo "  'from pymt_sft import SFT' will fail at runtime with:"
  echo "    ImportError: undefined symbol: _ZTV17BmiSoilFreezeThaw"
  echo

  # Locate the cmake source root — must contain CMakeLists.txt.
  _SFT_SRC=""
  for _candidate in "$SFT_ROOT" "$(cd "$SFT_ROOT/.." && pwd)" "$(cd "$SFT_LIB_DIR/.." && pwd)"; do
    [[ -f "$_candidate/CMakeLists.txt" ]] && { _SFT_SRC="$_candidate"; break; }
  done

  if [[ -z "$_SFT_SRC" ]]; then
    echo "ERROR: Cannot rebuild libsftbmi.so — no CMakeLists.txt found near SFT_ROOT." >&2
    echo "  Please rebuild SoilFreezeThaw manually with visibility flags:" >&2
    echo "    cd /path/to/SoilFreezeThaw" >&2
    echo "    cmake -S . -B build -DNGEN=ON \\" >&2
    echo "          -DCMAKE_CXX_VISIBILITY_PRESET=default \\" >&2
    echo "          -DCMAKE_VISIBILITY_INLINES_HIDDEN=OFF" >&2
    echo "    cmake --build build -j\$(nproc)" >&2
    echo "  Then re-run install.sh." >&2
    exit 1
  fi

  if ! have_cmd cmake; then
    echo "cmake not found; attempting direct g++ rebuild (no cmake required)..."

    # Find a working C++ compiler.
    _CXX="${CXX:-}"
    if [[ -z "$_CXX" ]]; then
      for _c in g++ c++ clang++; do
        have_cmd "$_c" && { _CXX="$_c"; break; }; done
    fi
    if [[ -z "$_CXX" ]]; then
      echo "ERROR: No C++ compiler (g++ / c++ / clang++) found on PATH." >&2
      echo "  Install build-essential or cmake and re-run." >&2
      exit 1
    fi

    # The NGEN build of SoilFreezeThaw compiles exactly two source files
    # (bmi_soil_freeze_thaw and soil_freeze_thaw); skip standalone / test mains.
    mapfile -t _SFT_SRCS < <(find "$_SFT_SRC/src" -maxdepth 1 \
        \( -name '*.cxx' -o -name '*.cpp' \) \
        ! -name '*main*' \
        -print 2>/dev/null | sort)

    if [[ ${#_SFT_SRCS[@]} -eq 0 ]]; then
      echo "ERROR: No C++ source files found in $_SFT_SRC/src" >&2
      echo "  Expected bmi_soil_freeze_thaw.cxx and soil_freeze_thaw.cxx." >&2
      exit 1
    fi
    echo "  Compiler : $_CXX"
    echo "  Sources  : ${_SFT_SRCS[*]}"

    _BUILD_DIR="${SCRIPT_DIR}/sftbmi_build"
    mkdir -p "$_BUILD_DIR"

    "$_CXX" -shared -fPIC -fvisibility=default -std=c++14 \
      -I"$_SFT_SRC/include" \
      -I"$_SFT_SRC/src" \
      -DBMI_ACTIVE \
      "${_SFT_SRCS[@]}" \
      -o "$_BUILD_DIR/libsftbmi.so"

    if ! _vtable_exported "$_BUILD_DIR/libsftbmi.so"; then
      echo "ERROR: Rebuilt library still does not export the vtable." >&2
      exit 1
    fi

    SFT_LIB_DIR="$_BUILD_DIR"
    echo "  New library with exported vtable: $SFT_LIB_DIR/libsftbmi.so"

  else
    # cmake IS available ─ use it.
    echo "Rebuilding libsftbmi.so from ${_SFT_SRC} with -DCMAKE_CXX_VISIBILITY_PRESET=default ..."
    _NCPUS="$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"

    cmake -S "$_SFT_SRC" -B "$SFT_LIB_DIR" \
      -DNGEN=ON \
      -DCMAKE_CXX_VISIBILITY_PRESET=default \
      -DCMAKE_VISIBILITY_INLINES_HIDDEN=OFF \
      ${CXX:+-DCMAKE_CXX_COMPILER="$CXX"}

    cmake --build "$SFT_LIB_DIR" -j"${_NCPUS}"

    # Re-check after rebuild.
    if ! _vtable_exported "$_LIBSFT"; then
      echo "ERROR: Rebuild completed but vtable is still not exported." >&2
      echo "  Please open an issue with the cmake output above." >&2
      exit 1
    fi
    echo "  Rebuild succeeded — vtable is now exported."
  fi  # end cmake / g++ branch
fi  # end vtable-check block

export SFT_ROOT
export SFT_LIB_DIR
export LD_LIBRARY_PATH="${SFT_LIB_DIR}:${LD_LIBRARY_PATH:-}"
export SFT_RPATH="${SFT_LIB_DIR}"

# ─── Compiler selection (mirrors CFE install.sh logic) ───────────────────────

_check_compiler() {
  command -v "$1" >/dev/null 2>&1 || return 1
  echo 'int main(){}' | "$1" -x c - -o /dev/null 2>/dev/null || return 1
}

if [[ -x /usr/bin/gcc ]] && _check_compiler /usr/bin/gcc; then
  export CC=/usr/bin/gcc
  [[ -x /usr/bin/g++ ]] && export CXX=/usr/bin/g++
  export LDSHARED="/usr/bin/gcc -shared"
  unset _CONDA_PYTHON_SYSCONFIGDATA_NAME
  unset LDFLAGS CFLAGS CXXFLAGS LD AR NM RANLIB 2>/dev/null || true
  echo "  Using system CC: $CC"
else
  echo "WARNING: /usr/bin/gcc not found; using conda env compiler." >&2
  # conda-forge's compiler_compat/ld wrapper enforces --no-undefined, which
  # breaks Python extension builds.  Python extension .so files on Linux
  # intentionally leave Python API symbols (PyTuple_Type, _Py_Dealloc, etc.)
  # unresolved at link time — they are provided at runtime by the interpreter.
  # The LDFLAGS env var is NOT enough here because setuptools reads linker
  # flags from conda's sysconfig data, not from LDFLAGS.
  #
  # Fix: remove compiler_compat from PATH so the build falls back to the
  # real system linker (/usr/bin/ld), which allows deferred Python symbols.
  _SAFE_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'compiler_compat' | paste -sd: -)"
  export PATH="$_SAFE_PATH"
  echo "  Stripped compiler_compat/ld from PATH — using system linker for Python extension"
  unset LDFLAGS CFLAGS CXXFLAGS 2>/dev/null || true
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo "Using active conda env : ${CONDA_PREFIX}"
echo "Using Python           : ${PYTHON_BIN}"
echo "Using tarball          : ${TARBALL}"
echo "Detected SFT_ROOT      : ${SFT_ROOT}"
echo "Detected SFT_LIB_DIR   : ${SFT_LIB_DIR}"

# ─── Build dependencies ───────────────────────────────────────────────────────

ensure_python_module() {
  "$PYTHON_BIN" -c "import $1" 2>/dev/null || {
    echo "  $2 not found — installing..."
    "$PYTHON_BIN" -m pip install "$2"
  }
}

echo "Checking build dependencies (numpy, Cython, setuptools, wheel)..."
ensure_python_module numpy    numpy
ensure_python_module Cython   cython
ensure_python_module setuptools setuptools
ensure_python_module wheel    wheel

# ─── Install ──────────────────────────────────────────────────────────────────
# SFT_RPATH is read by setup.py to bake an rpath into the Cython extension,
# so it finds libsftbmi.so at import time even before LD_LIBRARY_PATH is set.
#
# Conda's x86_64-conda-linux-gnu-c++ driver may still invoke
# $CONDA_PREFIX/compiler_compat/ld internally even after compiler_compat is
# removed from PATH.  That linker requires Python C-API symbols to resolve at
# link time.  Environment LDFLAGS are often ignored or placed too early by
# setuptools/sysconfig, so install from a patched unpacked sdist and inject the
# Python library directly into every setuptools Extension(...).  This ensures
# -L$CONDA_PREFIX/lib -lpythonX.Y appears in the correct part of the link line.
_PYVER="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
_PYLIB="${CONDA_PREFIX}/lib/libpython${_PYVER}.so"

if [[ -f "$_PYLIB" ]]; then
  echo "Patching sdist build to link Python extension against $_PYLIB ..."
  _PATCH_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pymt_sft_build.XXXXXX")"
  export TARBALL _PATCH_BUILD_DIR _PYVER CONDA_PREFIX

  "$PYTHON_BIN" - <<'PY'
import os, tarfile, pathlib, textwrap

tarball = pathlib.Path(os.environ["TARBALL"])
build_dir = pathlib.Path(os.environ["_PATCH_BUILD_DIR"])
pyver = os.environ["_PYVER"]
conda_prefix = os.environ["CONDA_PREFIX"]

with tarfile.open(tarball, "r:gz") as tf:
    # Safe-ish extraction: reject absolute paths and parent traversal.
    for member in tf.getmembers():
        p = pathlib.PurePosixPath(member.name)
        if p.is_absolute() or ".." in p.parts:
            raise RuntimeError(f"unsafe path in sdist: {member.name}")
    tf.extractall(build_dir)

setup_files = list(build_dir.glob("*/setup.py")) + list(build_dir.glob("setup.py"))
if not setup_files:
    raise RuntimeError("sdist does not contain setup.py; cannot patch Extension link args")
setup_py = setup_files[0]

patch = f'''
# ---- pymt_sft installer patch: conda compiler_compat/ld Python symbols ----
# Inject libpython into Extension(...) objects so conda's strict linker can
# resolve PyModuleDef_Init, PyObject_GenericGetDict, _Py_Dealloc, etc.
import os as _pymt_sft_os

def _pymt_sft_patch_extension_class(_Extension):
    _orig_init = _Extension.__init__
    def _patched_init(self, name, sources, *args, **kwargs):
        _libdir = _pymt_sft_os.environ.get("CONDA_PREFIX", {conda_prefix!r}) + "/lib"
        _pyver = _pymt_sft_os.environ.get("PYMT_SFT_PYVER", {pyver!r})
        _libname = "python" + _pyver
        kwargs["library_dirs"] = list(kwargs.get("library_dirs") or [])
        if _libdir not in kwargs["library_dirs"]:
            kwargs["library_dirs"].append(_libdir)
        kwargs["libraries"] = list(kwargs.get("libraries") or [])
        if _libname not in kwargs["libraries"]:
            kwargs["libraries"].append(_libname)
        kwargs["runtime_library_dirs"] = list(kwargs.get("runtime_library_dirs") or [])
        if _libdir not in kwargs["runtime_library_dirs"]:
            kwargs["runtime_library_dirs"].append(_libdir)
        return _orig_init(self, name, sources, *args, **kwargs)
    _Extension.__init__ = _patched_init

try:
    import setuptools.extension as _pymt_sft_setuptools_ext
    _pymt_sft_patch_extension_class(_pymt_sft_setuptools_ext.Extension)
except Exception:
    pass
try:
    import distutils.extension as _pymt_sft_distutils_ext
    _pymt_sft_patch_extension_class(_pymt_sft_distutils_ext.Extension)
except Exception:
    pass
# ---- end pymt_sft installer patch ----
'''

original = setup_py.read_text()
if "pymt_sft installer patch" not in original:
    setup_py.write_text(patch + "\n" + original)

print(setup_py.parent)
PY

  _PATCHED_SRC="$(_PATCH_BUILD_DIR="$_PATCH_BUILD_DIR" "$PYTHON_BIN" - <<'PY'
import os, pathlib
build_dir = pathlib.Path(os.environ["_PATCH_BUILD_DIR"])
setup_files = list(build_dir.glob("*/setup.py")) + list(build_dir.glob("setup.py"))
print(setup_files[0].parent)
PY
)"
  export PYMT_SFT_PYVER="$_PYVER"
  "$PYTHON_BIN" -m pip install --no-build-isolation --no-cache-dir "$_PATCHED_SRC"
else
  echo "WARNING: $_PYLIB not found; installing unpatched tarball." >&2
  "$PYTHON_BIN" -m pip install --no-build-isolation "$TARBALL"
fi

# ─── Persist LD_LIBRARY_PATH ──────────────────────────────────────────────────

ACTIVATE_D="${CONDA_PREFIX}/etc/conda/activate.d"
DEACTIVATE_D="${CONDA_PREFIX}/etc/conda/deactivate.d"
mkdir -p "$ACTIVATE_D" "$DEACTIVATE_D"

cat > "${ACTIVATE_D}/pymt_sft.sh" <<EOF
#!/usr/bin/env bash
# Added by pymt_sft installer
if [[ ":\${LD_LIBRARY_PATH:-}:" != *":${SFT_LIB_DIR}:"* ]]; then
  export LD_LIBRARY_PATH="${SFT_LIB_DIR}:\${LD_LIBRARY_PATH:-}"
fi
EOF

cat > "${DEACTIVATE_D}/pymt_sft.sh" <<'EOF'
#!/usr/bin/env bash
true
EOF

echo
echo "Install complete."
echo "Re-activate your env to pick up LD_LIBRARY_PATH:"
echo "  conda deactivate && conda activate ${CONDA_DEFAULT_ENV:-<your-env>}"
echo
echo "Quick test:"
echo "  ${PYTHON_BIN} -c \"from pymt_sft import SFT; print('pymt_sft OK')\""
