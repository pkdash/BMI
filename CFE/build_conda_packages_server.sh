#!/usr/bin/env bash
set -euo pipefail

# Build cfebmi and pymt_cfe conda packages on a Linux x86_64 server.
# Run this on the target JupyterHub server (or any Linux x86_64 machine).

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "ERROR: This script must run on a Linux x86_64 machine."
    echo "Current architecture: $(uname -m)"
    exit 1
fi

# Determine where the CFE directory is.
# This script assumes it is run from the directory that contains CFE/.
CFE_DIR="${CFE_DIR:-CFE}"

echo "=== Installing conda-build tools ==="
conda install -y conda-build boa -c conda-forge

echo "=== Building cfebmi ==="
conda mambabuild "${CFE_DIR}/conda-recipes/cfebmi" -c conda-forge

# Determine the Python version to build for. Default to 3.11 because that is
# what the JupyterHub server uses, but you can override with:
#   PYTHON_VERSION=3.12 ./build_conda_packages_server.sh
PY_VER="${PYTHON_VERSION:-3.11}"

echo "=== Building pymt_cfe for Python ${PY_VER} ==="
conda mambabuild "${CFE_DIR}/pymt_cfe/recipe" -c local -c conda-forge --python "${PY_VER}"

echo "=== Build complete ==="
echo "Packages should be in your conda-bld output directory."
echo "Check: $(conda build --output "${CFE_DIR}/conda-recipes/cfebmi" 2>/dev/null || echo '<see conda build output above>')"
