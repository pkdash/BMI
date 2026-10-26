#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_ueb"
PATCH_SCRIPT="${ROOT_DIR}/post_babelize_patch.sh"
BABEL_TOML="${ROOT_DIR}/babel.toml"

[[ -f "${BABEL_TOML}" ]] || { echo "ERROR: Missing ${BABEL_TOML}" >&2; exit 1; }
[[ -x "${PATCH_SCRIPT}" ]] || {
  echo "ERROR: Missing or non-executable ${PATCH_SCRIPT}" >&2
  echo "Run: chmod +x post_babelize_patch.sh regen_and_build.sh install.sh" >&2
  exit 1
}
command -v babelize >/dev/null || { echo "ERROR: babelize not found" >&2; exit 1; }
command -v uv >/dev/null || { echo "ERROR: uv not found" >&2; exit 1; }

echo "[1/3] Regenerating pymt_ueb..."
rm -rf "${PKG_DIR}"
cd "${ROOT_DIR}"
babelize init "${BABEL_TOML}"

echo "[2/3] Applying UEB-specific patches..."
"${PATCH_SCRIPT}"

echo "[3/3] Building sdist and wheel..."
cd "${PKG_DIR}"
rm -rf build dist *.egg-info
uv build

echo
echo "Built:"
ls -lh dist/
