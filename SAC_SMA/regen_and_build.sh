#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_sac_sma"
PATCH_SCRIPT="${ROOT_DIR}/post_babelize_patch.sh"
BABEL_TOML="${ROOT_DIR}/babel.toml"

[[ -f "${BABEL_TOML}" ]] || {
  echo "ERROR: babel.toml not found at ${BABEL_TOML}" >&2
  exit 1
}
command -v babelize >/dev/null 2>&1 || {
  echo "ERROR: babelize not found in PATH" >&2
  exit 1
}
command -v uv >/dev/null 2>&1 || {
  echo "ERROR: uv not found in PATH" >&2
  exit 1
}
[[ -x "${PATCH_SCRIPT}" ]] || {
  echo "ERROR: Patch script is missing or not executable: ${PATCH_SCRIPT}" >&2
  exit 1
}

echo "[1/3] Regenerating pymt_sac_sma with Babelizer..."
rm -rf "${PKG_DIR}"
cd "${ROOT_DIR}"
babelize init "${BABEL_TOML}"

# Avoid nested repository metadata when this workflow is stored in another repo.
rm -rf "${PKG_DIR}/.git"

echo "[2/3] Applying Sac-SMA-specific patches..."
"${PATCH_SCRIPT}"

echo "[3/3] Building sdist and wheel..."
cd "${PKG_DIR}"
rm -rf build dist *.egg-info
uv build

echo
echo "Built artifacts:"
ls -lh "${PKG_DIR}/dist"
