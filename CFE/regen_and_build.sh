#!/usr/bin/env bash
set -euo pipefail

# One-shot helper:
#  1) Regenerate wrapper with Babelizer
#  2) Reapply local patches
#  3) Build sdist+wheel with uv

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_cfe"
PATCH_SCRIPT="${ROOT_DIR}/post_babelize_patch.sh"
BABEL_TOML="${ROOT_DIR}/babel.toml"

if [[ ! -f "${BABEL_TOML}" ]]; then
  echo "ERROR: babel.toml not found at ${BABEL_TOML}" >&2
  exit 1
fi
if [[ ! -x "${PATCH_SCRIPT}" ]]; then
  echo "ERROR: Patch script missing or not executable: ${PATCH_SCRIPT}" >&2
  exit 1
fi
if ! command -v babelize >/dev/null 2>&1; then
  echo "ERROR: 'babelize' command not found in PATH." >&2
  exit 1
fi
if ! command -v uv >/dev/null 2>&1; then
  echo "ERROR: 'uv' command not found in PATH." >&2
  exit 1
fi

echo "[1/3] Regenerating pymt_cfe with Babelizer..."
if [[ -d "${PKG_DIR}" ]]; then
  echo "- Removing existing ${PKG_DIR} (clean regeneration)"
  rm -rf "${PKG_DIR}"
fi
cd "${ROOT_DIR}"
babelize init "${BABEL_TOML}"

echo "[2/3] Reapplying local patches..."
"${PATCH_SCRIPT}"

echo "[3/3] Building artifacts with uv..."
cd "${PKG_DIR}"
rm -rf build dist *.egg-info
uv build

echo
echo "Done. Built artifacts:"
ls -1 "${PKG_DIR}/dist" || true
