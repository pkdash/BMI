#!/usr/bin/env bash
set -euo pipefail

# One-shot helper for NOAH_OWP wrapper development:
#  1) Regenerate wrapper with Babelizer
#  2) Reapply local patches (if patch script exists)
#  3) Build sdist+wheel with uv

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_noah_owp"
PATCH_SCRIPT="${ROOT_DIR}/post_babelize_patch.sh"
BABEL_TOML="${ROOT_DIR}/babel.toml"

if [[ ! -f "${BABEL_TOML}" ]]; then
  echo "ERROR: babel.toml not found at ${BABEL_TOML}" >&2
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

echo "[1/3] Regenerating pymt_noah_owp with Babelizer..."
if [[ -d "${PKG_DIR}" ]]; then
  echo "- Removing existing ${PKG_DIR} (clean regeneration)"
  rm -rf "${PKG_DIR}"
fi
cd "${ROOT_DIR}"
babelize init "${BABEL_TOML}"

# Babelizer templates may initialize a nested git repo; remove it for monorepo usage.
if [[ -d "${PKG_DIR}/.git" ]]; then
  rm -rf "${PKG_DIR}/.git"
fi

echo "[2/3] Reapplying local patches (if present)..."
if [[ -x "${PATCH_SCRIPT}" ]]; then
  "${PATCH_SCRIPT}"
else
  echo "- No executable patch script found at ${PATCH_SCRIPT}; skipping"
fi

echo "[3/3] Building artifacts with uv..."
cd "${PKG_DIR}"
rm -rf build dist *.egg-info
uv build

echo
echo "Done. Built artifacts:"
ls -1 "${PKG_DIR}/dist" || true
