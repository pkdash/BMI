#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python)}"

[[ -x "${PYTHON_BIN}" ]] || {
  echo "ERROR: Python not found." >&2
  exit 1
}

mapfile -t TARBALLS < <(ls -1t "${SCRIPT_DIR}"/pymt_sac_sma-*.tar.gz 2>/dev/null || true)
[[ ${#TARBALLS[@]} -gt 0 ]] || {
  echo "ERROR: No pymt_sac_sma-*.tar.gz found in ${SCRIPT_DIR}" >&2
  exit 1
}
TARBALL="${TARBALLS[0]}"

SAC_SMA_ROOT="${SAC_SMA_ROOT:-}"
SAC_SMA_LIB_DIR="${SAC_SMA_LIB_DIR:-}"
SAC_SMA_BMI_DIR="${SAC_SMA_BMI_DIR:-}"
ISO_C_FORTRAN_BMI_PATH="${ISO_C_FORTRAN_BMI_PATH:-}"

# Locate libsacbmi.so.
if [[ -z "${SAC_SMA_LIB_DIR}" ]]; then
  for candidate in \
    "$HOME/NextGenVS/ngen/extern/sac-sma/cmake_build" \
    "$HOME/NextGenVS/ngen/extern/sac_sma/cmake_build" \
    "$HOME/NextGenVS/sac-sma/cmake_build" \
    "/workspace/sac-sma/cmake_build"; do
    if compgen -G "${candidate}/libsacbmi.so*" >/dev/null 2>&1; then
      SAC_SMA_LIB_DIR="${candidate}"
      break
    fi
  done
fi

if [[ -z "${SAC_SMA_LIB_DIR}" ]]; then
  hit="$(find "$HOME" /workspace /opt /usr/local \
    -type f -name 'libsacbmi.so*' 2>/dev/null | head -n1 || true)"
  [[ -n "${hit}" ]] && SAC_SMA_LIB_DIR="$(dirname "${hit}")"
fi

[[ -n "${SAC_SMA_LIB_DIR}" ]] || {
  echo "ERROR: Could not locate libsacbmi.so." >&2
  echo "Set SAC_SMA_LIB_DIR to its containing directory." >&2
  exit 1
}

# Locate source root.
if [[ -z "${SAC_SMA_ROOT}" ]]; then
  for candidate in \
    "$(cd "${SAC_SMA_LIB_DIR}/.." 2>/dev/null && pwd || true)" \
    "$HOME/NextGenVS/ngen/extern/sac-sma" \
    "$HOME/NextGenVS/sac-sma" \
    "/workspace/sac-sma"; do
    if [[ -f "${candidate}/src/bmi/bmi_sac.f90" ]]; then
      SAC_SMA_ROOT="${candidate}"
      break
    fi
  done
fi

[[ -f "${SAC_SMA_ROOT}/src/bmi/bmi_sac.f90" ]] || {
  echo "ERROR: Could not locate SAC_SMA_ROOT/src/bmi/bmi_sac.f90." >&2
  exit 1
}

# Locate Fortran module output directory.
if [[ -z "${SAC_SMA_BMI_DIR}" ]]; then
  for candidate in \
    "${SAC_SMA_LIB_DIR}/mod" \
    "${SAC_SMA_LIB_DIR}" \
    "${SAC_SMA_ROOT}/cmake_build/mod" \
    "${SAC_SMA_ROOT}/cmake_build"; do
    if find "${candidate}" -maxdepth 2 \
      \( -iname 'bmi_sac_module.mod' -o -iname 'bmif_2_0_iso.mod' \) \
      -print -quit 2>/dev/null | grep -q .; then
      SAC_SMA_BMI_DIR="${candidate}"
      break
    fi
  done
fi

if [[ -z "${SAC_SMA_BMI_DIR}" ]]; then
  hit="$(find "${SAC_SMA_ROOT}" -type f \
    \( -iname 'bmi_sac_module.mod' -o -iname 'bmif_2_0_iso.mod' \) \
    2>/dev/null | head -n1 || true)"
  [[ -n "${hit}" ]] && SAC_SMA_BMI_DIR="$(dirname "${hit}")"
fi

[[ -n "${SAC_SMA_BMI_DIR}" ]] || {
  echo "ERROR: Could not locate Sac-SMA Fortran .mod files." >&2
  exit 1
}

# Locate iso_c_fortran_bmi source.
if [[ -z "${ISO_C_FORTRAN_BMI_PATH}" ]]; then
  for candidate in \
    "$HOME/NextGenVS/ngen/extern/iso_c_fortran_bmi" \
    "$(dirname "${SAC_SMA_ROOT}")/iso_c_fortran_bmi" \
    "/workspace/ngen/extern/iso_c_fortran_bmi"; do
    if [[ -d "${candidate}" ]]; then
      ISO_C_FORTRAN_BMI_PATH="${candidate}"
      break
    fi
  done
fi

export SAC_SMA_ROOT SAC_SMA_LIB_DIR SAC_SMA_BMI_DIR ISO_C_FORTRAN_BMI_PATH
export SAC_SMA_INCLUDE_DIR="${SAC_SMA_ROOT}/src/bmi"
export LD_LIBRARY_PATH="${SAC_SMA_LIB_DIR}:${LD_LIBRARY_PATH:-}"
export FC="${FC:-/usr/bin/gfortran}"
export CC="${CC:-/usr/bin/gcc}"

echo "Python                 : ${PYTHON_BIN}"
echo "Tarball                : ${TARBALL}"
echo "SAC_SMA_ROOT           : ${SAC_SMA_ROOT}"
echo "SAC_SMA_LIB_DIR        : ${SAC_SMA_LIB_DIR}"
echo "SAC_SMA_BMI_DIR        : ${SAC_SMA_BMI_DIR}"
echo "ISO_C_FORTRAN_BMI_PATH : ${ISO_C_FORTRAN_BMI_PATH:-<not found>}"
echo "Fortran compiler       : ${FC}"

"${PYTHON_BIN}" -m pip install \
  "numpy==1.26.4" \
  "Cython==3.0.11" \
  setuptools \
  wheel

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pymt_sac_sma_build.XXXXXX")"
trap 'rm -rf "${BUILD_DIR}"' EXIT

tar -xzf "${TARBALL}" -C "${BUILD_DIR}"
SRC_DIR="$(find "${BUILD_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n1)"
[[ -n "${SRC_DIR}" ]] || {
  echo "ERROR: Could not unpack source distribution." >&2
  exit 1
}

# Regenerate C locally to match the target NumPy/Cython environment.
rm -f "${SRC_DIR}/pymt_sac_sma/lib/sac_sma.c"

"${PYTHON_BIN}" -m pip install \
  --no-build-isolation \
  --no-cache-dir \
  "${SRC_DIR}"

echo
echo "Install complete."
echo "Test from outside the source folder:"
echo "  cd ~"
echo "  ${PYTHON_BIN} -c \"from pymt_sac_sma import SAC_SMA; print(SAC_SMA().get_component_name())\""
