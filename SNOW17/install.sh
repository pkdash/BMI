#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ -n "${CONDA_PREFIX:-}" ]] || { echo "ERROR: CONDA_PREFIX is empty. For pyenv: export CONDA_PREFIX=\$(pyenv prefix)" >&2; exit 1; }
PYTHON_BIN="${CONDA_PREFIX}/bin/python"
[[ -x "${PYTHON_BIN}" ]] || { echo "ERROR: Python not found at ${PYTHON_BIN}" >&2; exit 1; }
mapfile -t TARBALLS < <(ls -1t "${SCRIPT_DIR}"/pymt_snow17-*.tar.gz 2>/dev/null || true)
[[ ${#TARBALLS[@]} -gt 0 ]] || { echo "ERROR: No pymt_snow17-*.tar.gz found in ${SCRIPT_DIR}" >&2; exit 1; }
TARBALL="${TARBALLS[0]}"
find_first_file(){ local root="$1"; local pattern="$2"; [[ -d "$root" ]] || return 1; find "$root" -type f -name "$pattern" 2>/dev/null | head -n1; }
SNOW17_LIB_DIR="${SNOW17_LIB_DIR:-}"
if [[ -z "$SNOW17_LIB_DIR" || ! -e "$SNOW17_LIB_DIR/libsnow17bmi.so" ]]; then
  for root in "$HOME/NextGenVS/ngen/extern/snow17" "/workspace/snow17" "$HOME" "/usr/local" "/usr"; do
    hit="$(find_first_file "$root" 'libsnow17bmi.so*' || true)"; [[ -n "$hit" ]] && { SNOW17_LIB_DIR="$(dirname "$hit")"; break; }
  done
fi
[[ -n "$SNOW17_LIB_DIR" && -e "$SNOW17_LIB_DIR/libsnow17bmi.so" ]] || { echo "ERROR: Could not locate libsnow17bmi.so*." >&2; exit 1; }
SNOW17_ROOT="${SNOW17_ROOT:-}"
if [[ -z "$SNOW17_ROOT" ]]; then
  for candidate in "$(cd "$SNOW17_LIB_DIR/.." && pwd 2>/dev/null || true)" "$HOME/NextGenVS/ngen/extern/snow17" "/workspace/snow17"; do
    [[ -f "$candidate/src/bmi/bmi_snow17.f90" ]] && { SNOW17_ROOT="$candidate"; break; }
  done
fi
[[ -n "$SNOW17_ROOT" && -f "$SNOW17_ROOT/src/bmi/bmi_snow17.f90" ]] || { echo "ERROR: Could not locate SNOW17_ROOT/src/bmi/bmi_snow17.f90" >&2; exit 1; }
SNOW17_BMI_DIR="${SNOW17_BMI_DIR:-$SNOW17_LIB_DIR}"
SNOW17_MOD_DIR="${SNOW17_MOD_DIR:-$SNOW17_LIB_DIR/iso_c_bmi}"
export SNOW17_ROOT SNOW17_LIB_DIR SNOW17_BMI_DIR SNOW17_MOD_DIR
export LD_LIBRARY_PATH="${SNOW17_LIB_DIR}:${SNOW17_MOD_DIR}:${LD_LIBRARY_PATH:-}"
[[ -x /usr/bin/gcc ]] && export CC=/usr/bin/gcc LDSHARED="/usr/bin/gcc -shared"
if [[ -x /usr/bin/gfortran ]]; then export FC=/usr/bin/gfortran; elif command -v gfortran >/dev/null; then export FC="$(command -v gfortran)"; else echo "ERROR: gfortran not found" >&2; exit 1; fi
echo "Using tarball          : ${TARBALL}"
echo "Detected SNOW17_ROOT   : ${SNOW17_ROOT}"
echo "Detected SNOW17_LIB_DIR: ${SNOW17_LIB_DIR}"
echo "Detected SNOW17_BMI_DIR: ${SNOW17_BMI_DIR}"
echo "Detected SNOW17_MOD_DIR: ${SNOW17_MOD_DIR}"
echo "Fortran compiler       : ${FC}"
"$PYTHON_BIN" -m pip install --upgrade setuptools wheel >/dev/null
"$PYTHON_BIN" -c "import numpy" 2>/dev/null || "$PYTHON_BIN" -m pip install numpy
"$PYTHON_BIN" -c "import Cython" 2>/dev/null || "$PYTHON_BIN" -m pip install cython
"$PYTHON_BIN" -m pip install --no-build-isolation --force-reinstall "$TARBALL"
echo "Install complete. Test: ${PYTHON_BIN} -c \"from pymt_snow17 import SNOW17; print('pymt_snow17 OK')\""
