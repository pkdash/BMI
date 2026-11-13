#!/usr/bin/env bash
# Install the generated BMI wrapper sources into a Babelizer-generated package.
#
# Single source of truth: common/install_wrapper.sh.  common/render_wrappers.py
# copies it to <MODEL>/wrapper/install.sh next to the rendered <module>.pyx,
# _bmi_arrays.py and bmi_ptr.pxi; each <MODEL>/post_babelize_patch.sh runs it.
# The files are vendored per model because the Docker workflow mounts only the
# model directory.
#
# Usage: wrapper/install.sh <PKG_DIR>     (e.g. .../CFE/pymt_cfe)
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <generated package directory, e.g. ./pymt_cfe>" >&2
  exit 2
fi

WRAPPER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${1%/}"
PKG="$(basename -- "${PKG_DIR}")"
LIB_DIR="${PKG_DIR}/${PKG}/lib"

shopt -s nullglob
pyx_files=("${WRAPPER_DIR}"/*.pyx)
shopt -u nullglob
if [[ ${#pyx_files[@]} -ne 1 ]]; then
  echo "ERROR: expected exactly one .pyx in ${WRAPPER_DIR}; run: python common/render_wrappers.py" >&2
  exit 1
fi
MODULE="$(basename -- "${pyx_files[0]}" .pyx)"

mkdir -p "${LIB_DIR}"
for f in "${MODULE}.pyx" _bmi_arrays.py bmi_ptr.pxi; do
  if [[ ! -f "${WRAPPER_DIR}/${f}" ]]; then
    echo "ERROR: ${WRAPPER_DIR}/${f} not found; run: python common/render_wrappers.py" >&2
    exit 1
  fi
  cp "${WRAPPER_DIR}/${f}" "${LIB_DIR}/${f}"
done

# Remove stale Cython output so the build regenerates it from the new .pyx
# (the sdist still ships freshly generated C/C++ sources).
rm -f "${LIB_DIR}/${MODULE}.c" "${LIB_DIR}/${MODULE}.cpp"

# bmi_ptr.pxi is needed to build from the sdist.
MANIFEST_IN="${PKG_DIR}/MANIFEST.in"
if [[ -f "${MANIFEST_IN}" ]] && ! grep -qF "recursive-include ${PKG} *.pxi" "${MANIFEST_IN}"; then
  echo "recursive-include ${PKG} *.pxi" >> "${MANIFEST_IN}"
fi

echo "- Installed generated BMI wrapper ${MODULE}.pyx into ${LIB_DIR}"
