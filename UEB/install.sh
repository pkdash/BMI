#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python)}"

[[ -x "${PYTHON_BIN}" ]] || { echo "ERROR: Python not found" >&2; exit 1; }

mapfile -t TARBALLS < <(ls -1t "${SCRIPT_DIR}"/pymt_ueb-*.tar.gz 2>/dev/null || true)
[[ ${#TARBALLS[@]} -gt 0 ]] || {
  echo "ERROR: No pymt_ueb-*.tar.gz found in ${SCRIPT_DIR}" >&2
  exit 1
}
TARBALL="${TARBALLS[0]}"

UEB_ROOT="${UEB_ROOT:-}"
UEB_LIB_DIR="${UEB_LIB_DIR:-}"

if [[ -z "${UEB_LIB_DIR}" ]]; then
  for candidate in \
      "$HOME/NextGenVS/ueb_bmi/cmake_build/src" \
      "$HOME/ueb_bmi/cmake_build/src" \
      "/workspace/ueb_bmi/cmake_build/src"; do
    if compgen -G "${candidate}/libbmiuebcxx.so*" >/dev/null 2>&1; then
      UEB_LIB_DIR="${candidate}"
      break
    fi
  done
fi

if [[ -z "${UEB_LIB_DIR}" ]]; then
  hit="$(find "$HOME" /workspace /opt /usr/local \
      -type f -name 'libbmiuebcxx.so*' 2>/dev/null | head -n1 || true)"
  [[ -n "${hit}" ]] && UEB_LIB_DIR="$(dirname "${hit}")"
fi

[[ -n "${UEB_LIB_DIR}" ]] || {
  echo "ERROR: Could not find libbmiuebcxx.so." >&2
  echo "Set it explicitly:" >&2
  echo "  export UEB_LIB_DIR=/path/to/ueb_bmi/cmake_build/src" >&2
  exit 1
}

if [[ -z "${UEB_ROOT}" ]]; then
  for candidate in \
      "$(cd "${UEB_LIB_DIR}/../.." 2>/dev/null && pwd || true)" \
      "$HOME/NextGenVS/ueb_bmi" \
      "$HOME/ueb_bmi" \
      "/workspace/ueb_bmi"; do
    if [[ -f "${candidate}/src/bmi/bmi_ueb.hxx" ]]; then
      UEB_ROOT="${candidate}"
      break
    fi
  done
fi

[[ -f "${UEB_ROOT}/src/bmi/bmi_ueb.hxx" ]] || {
  echo "ERROR: Could not locate UEB source root containing src/bmi/bmi_ueb.hxx." >&2
  echo "Set it explicitly:" >&2
  echo "  export UEB_ROOT=/path/to/ueb_bmi" >&2
  exit 1
}

BMICXX_INCLUDE_DIRS="${BMICXX_INCLUDE_DIRS:-}"
if [[ -z "${BMICXX_INCLUDE_DIRS}" ]]; then
  for candidate in \
      "$(dirname "${UEB_ROOT}")/bmi-cxx" \
      "$HOME/NextGenVS/ngen/extern/bmi-cxx" \
      "$HOME/NextGenVS/bmi-cxx" \
      "/workspace/bmi-cxx"; do
    if [[ -f "${candidate}/bmi.hxx" ]]; then
      BMICXX_INCLUDE_DIRS="${candidate}"
      break
    fi
  done
fi

[[ -f "${BMICXX_INCLUDE_DIRS}/bmi.hxx" ]] || {
  echo "ERROR: Could not locate bmi-cxx/bmi.hxx." >&2
  echo "Set BMICXX_INCLUDE_DIRS to the directory containing bmi.hxx." >&2
  exit 1
}

export UEB_ROOT UEB_LIB_DIR BMICXX_INCLUDE_DIRS
export UEB_INCLUDE_DIR="${UEB_ROOT}/src/bmi"
export UEB_RPATH="${UEB_LIB_DIR}"
export LD_LIBRARY_PATH="${UEB_LIB_DIR}:${LD_LIBRARY_PATH:-}"

echo "Python              : ${PYTHON_BIN}"
echo "Tarball             : ${TARBALL}"
echo "UEB_ROOT            : ${UEB_ROOT}"
echo "UEB_LIB_DIR         : ${UEB_LIB_DIR}"
echo "BMICXX_INCLUDE_DIRS : ${BMICXX_INCLUDE_DIRS}"

"${PYTHON_BIN}" -m pip install --upgrade pip
"${PYTHON_BIN}" -m pip install numpy cython setuptools wheel
"${PYTHON_BIN}" -m pip install --no-build-isolation --no-cache-dir "${TARBALL}"

echo
echo "Install complete."
echo "Runtime test:"
echo "  export LD_LIBRARY_PATH=\"${UEB_LIB_DIR}:\$LD_LIBRARY_PATH\""
echo "  ${PYTHON_BIN} -c \"from pymt_ueb import UEB; m=UEB(); print(m.get_component_name())\""
