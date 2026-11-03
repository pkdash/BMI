#!/usr/bin/env bash
set -euo pipefail

# Install pymt_smp from a local sdist tarball into the CURRENT active env.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${CONDA_PREFIX:-}" ]]; then
  echo "ERROR: CONDA_PREFIX is empty." >&2
  echo "For your pyenv workflow, run:" >&2
  echo "  export CONDA_PREFIX=\$(pyenv prefix)" >&2
  exit 1
fi

PYTHON_BIN="${CONDA_PREFIX}/bin/python"
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "ERROR: Active env does not contain executable Python: ${PYTHON_BIN}" >&2
  exit 1
fi

mapfile -t TARBALLS < <(ls -1t "${SCRIPT_DIR}"/pymt_smp-*.tar.gz 2>/dev/null || true)
if [[ ${#TARBALLS[@]} -eq 0 ]]; then
  echo "ERROR: No pymt_smp-*.tar.gz found in ${SCRIPT_DIR}" >&2
  echo "This installer is for SMP only. Expected: pymt_smp-0.1.tar.gz" >&2
  exit 1
fi
TARBALL="${TARBALLS[0]}"

have_cmd() { command -v "$1" >/dev/null 2>&1; }

pkg_config_library_dirs() {
  if have_cmd pkg-config && pkg-config --exists smpbmi 2>/dev/null; then
    pkg-config --libs-only-L smpbmi 2>/dev/null | tr ' ' '\n' | sed -n 's/^-L//p'
  fi
}

first_existing_libdir() {
  local d
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    if compgen -G "$d/libsmpbmi.so*" > /dev/null; then
      echo "$d"; return 0
    fi
  done
  return 1
}

SMP_LIB_DIR="${SMP_LIB_DIR:-}"
if [[ -n "$SMP_LIB_DIR" ]] && compgen -G "$SMP_LIB_DIR/libsmpbmi.so*" > /dev/null 2>&1; then
  :
else
  if SMP_LIB_DIR="$(pkg_config_library_dirs | first_existing_libdir 2>/dev/null || true)"; then
    :
  fi
fi

if [[ -z "$SMP_LIB_DIR" ]]; then
  SEARCH_ROOTS=(
    "/workspace/smp/build"
    "/workspace/smp"
    "$HOME/NextGenVS/ngen/extern/SoilMoistureProfiles"
    "$HOME"
    "/opt"
    "/usr/local"
    "/usr"
  )
  for root in "${SEARCH_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    hit="$(find "$root" -type f \( -name 'libsmpbmi.so' -o -name 'libsmpbmi.so.*' \) 2>/dev/null | head -n1 || true)"
    if [[ -n "$hit" ]]; then
      SMP_LIB_DIR="$(dirname "$hit")"
      break
    fi
  done
fi

if [[ -z "$SMP_LIB_DIR" ]]; then
  echo "ERROR: Could not locate libsmpbmi.so*." >&2
  echo "Set SMP_LIB_DIR and re-run:" >&2
  echo "  export SMP_LIB_DIR=/path/to/SoilMoistureProfiles/cmake_build" >&2
  exit 1
fi

SMP_ROOT="${SMP_ROOT:-}"
if [[ -z "$SMP_ROOT" ]]; then
  for candidate in \
    "$(cd "$SMP_LIB_DIR/.." && pwd 2>/dev/null || true)" \
    "$(cd "$SMP_LIB_DIR/../SoilMoistureProfiles" && pwd 2>/dev/null || true)" \
    "$(cd "$SMP_LIB_DIR/../.." && pwd 2>/dev/null || true)"; do
    [[ -n "$candidate" ]] || continue
    if [[ -f "$candidate/include/bmi_soil_moisture_profile.hxx" ]]; then
      SMP_ROOT="$candidate"; break
    fi
  done
fi

if [[ -z "$SMP_ROOT" || ! -f "$SMP_ROOT/include/bmi_soil_moisture_profile.hxx" ]]; then
  echo "ERROR: Could not determine SMP_ROOT containing include/bmi_soil_moisture_profile.hxx" >&2
  echo "Set SMP_ROOT manually and re-run:" >&2
  echo "  export SMP_ROOT=/path/to/SoilMoistureProfiles/SoilMoistureProfiles" >&2
  exit 1
fi

export SMP_ROOT
export SMP_LIB_DIR
export SMP_INCLUDE_DIR="${SMP_ROOT}/include"
export LD_LIBRARY_PATH="${SMP_LIB_DIR}:${LD_LIBRARY_PATH:-}"
export SMP_RPATH="${SMP_LIB_DIR}"

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
  echo "WARNING: /usr/bin/gcc not found; using env compiler." >&2
  _SAFE_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'compiler_compat' | paste -sd: -)"
  export PATH="$_SAFE_PATH"
  unset LDFLAGS CFLAGS CXXFLAGS 2>/dev/null || true
fi

echo "Using active env       : ${CONDA_PREFIX}"
echo "Using Python           : ${PYTHON_BIN}"
echo "Using tarball          : ${TARBALL}"
echo "Detected SMP_ROOT      : ${SMP_ROOT}"
echo "Detected SMP_LIB_DIR   : ${SMP_LIB_DIR}"

ensure_python_module() {
  "$PYTHON_BIN" -c "import $1" 2>/dev/null || {
    echo "  $2 not found — installing..."
    "$PYTHON_BIN" -m pip install "$2"
  }
}

echo "Checking build dependencies (numpy, Cython, setuptools, wheel)..."
ensure_python_module numpy numpy
ensure_python_module Cython cython
ensure_python_module setuptools setuptools
ensure_python_module wheel wheel

_PYVER="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
_PYLIB="${CONDA_PREFIX}/lib/libpython${_PYVER}.so"

if [[ -f "$_PYLIB" ]]; then
  echo "Patching sdist build to link Python extension against $_PYLIB ..."
  _PATCH_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pymt_smp_build.XXXXXX")"
  export TARBALL _PATCH_BUILD_DIR _PYVER CONDA_PREFIX

  "$PYTHON_BIN" - <<'PY'
import os, tarfile, pathlib

tarball = pathlib.Path(os.environ["TARBALL"])
build_dir = pathlib.Path(os.environ["_PATCH_BUILD_DIR"])

with tarfile.open(tarball, "r:gz") as tf:
    for member in tf.getmembers():
        p = pathlib.PurePosixPath(member.name)
        if p.is_absolute() or ".." in p.parts:
            raise RuntimeError(f"unsafe path in sdist: {member.name}")
    tf.extractall(build_dir)

setup_files = list(build_dir.glob("*/setup.py")) + list(build_dir.glob("setup.py"))
if not setup_files:
    raise RuntimeError("sdist does not contain setup.py")
setup_py = setup_files[0]

patch = r