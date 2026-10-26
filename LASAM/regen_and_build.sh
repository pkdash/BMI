#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/pymt_lasam"
rm -rf "$PKG_DIR"
cd "$ROOT_DIR"
babelize init babel.toml
./post_babelize_patch.sh
cd "$PKG_DIR"
rm -rf build dist *.egg-info
uv build
ls -lh dist/
