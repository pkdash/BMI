#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_snow17"
PATCH_SCRIPT="${ROOT_DIR}/post_babelize_patch.sh"
BABEL_TOML="${ROOT_DIR}/babel.toml"

[[ -f "${BABEL_TOML}" ]] || { echo "ERROR: babel.toml not found" >&2; exit 1; }
[[ -x "${PATCH_SCRIPT}" ]] || { echo "ERROR: post_babelize_patch.sh not executable" >&2; exit 1; }
command -v babelize >/dev/null 2>&1 || { echo "ERROR: babelize not found" >&2; exit 1; }
command -v uv >/dev/null 2>&1 || { echo "ERROR: uv not found" >&2; exit 1; }

echo "[1/3] Regenerating pymt_snow17 with Babelizer..."
rm -rf "${PKG_DIR}"
cd "${ROOT_DIR}"
babelize init "${BABEL_TOML}"
rm -rf "${PKG_DIR}/.git" 2>/dev/null || true

echo "[2/3] Reapplying local Snow17 patches..."
"${PATCH_SCRIPT}"

echo "[3/3] Building artifacts with uv..."
cd "${PKG_DIR}"
rm -rf build dist *.egg-info
uv build

echo
echo "Done. Built artifacts:"
ls -1 "${PKG_DIR}/dist" || true
