#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python)}"
TARBALL="$(ls -1t "$SCRIPT_DIR"/pymt_lasam-*.tar.gz 2>/dev/null | head -n1 || true)"
[[ -n "$TARBALL" ]] || { echo "ERROR: No pymt_lasam-*.tar.gz beside install.sh" >&2; exit 1; }
LASAM_ROOT="${LASAM_ROOT:-}"
LASAM_LIB_DIR="${LASAM_LIB_DIR:-}"
if [[ -z "$LASAM_LIB_DIR" ]]; then
  for d in "$HOME/NextGenVS/ngen/extern/LGAR-C/cmake_build" "$HOME/NextGenVS/ngen/extern/lgar-c/cmake_build" "$HOME/NextGenVS/LGAR-C/build" /workspace/LGAR-C/build; do
    compgen -G "$d/liblasambmi.so*" >/dev/null 2>&1 && { LASAM_LIB_DIR="$d"; break; }
  done
fi
[[ -n "$LASAM_LIB_DIR" ]] || { echo "ERROR: liblasambmi.so not found; set LASAM_LIB_DIR" >&2; exit 1; }
if [[ -z "$LASAM_ROOT" ]]; then
  for d in "$(cd "$LASAM_LIB_DIR/.." && pwd)" "$HOME/NextGenVS/ngen/extern/LGAR-C" "$HOME/NextGenVS/LGAR-C" /workspace/LGAR-C; do
    [[ -f "$d/include/bmi_lgar.hxx" ]] && { LASAM_ROOT="$d"; break; }
  done
fi
[[ -f "$LASAM_ROOT/include/bmi_lgar.hxx" ]] || { echo "ERROR: LASAM_ROOT/include/bmi_lgar.hxx not found" >&2; exit 1; }
export LASAM_ROOT LASAM_LIB_DIR LASAM_INCLUDE_DIR="$LASAM_ROOT/include" LASAM_BMI_DIR="$LASAM_ROOT/bmi" LASAM_RPATH="$LASAM_LIB_DIR"
export LD_LIBRARY_PATH="$LASAM_LIB_DIR:${LD_LIBRARY_PATH:-}"
export CC="${CC:-/usr/bin/gcc}" CXX="${CXX:-/usr/bin/g++}"
"$PYTHON_BIN" -m pip install "numpy==1.26.4" "Cython==3.0.11" setuptools wheel
BUILD_DIR="$(mktemp -d)"; trap 'rm -rf "$BUILD_DIR"' EXIT
tar -xzf "$TARBALL" -C "$BUILD_DIR"
SRC_DIR="$(find "$BUILD_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1)"
rm -f "$SRC_DIR/pymt_lasam/lib/lasam.cpp"
"$PYTHON_BIN" -m pip install --no-build-isolation --no-cache-dir "$SRC_DIR"
echo "Install complete. Test from ~ with:"
echo "$PYTHON_BIN -c 'from pymt_lasam import LASAM; print(LASAM().get_component_name())'"
