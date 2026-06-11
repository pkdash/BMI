#!/usr/bin/env bash
set -euo pipefail

# Build cfebmi and pymt_cfe conda packages inside the Docker container.
# This script assumes it runs in the micromamba-based CFE container
# with the workspace mounted at /workspace.

cd /workspace

echo "=== Installing conda-build tools ==="
micromamba install -y -n base -c conda-forge boa conda-build conda-verify

echo "=== Building cfebmi ==="
conda mambabuild CFE/conda-recipes/cfebmi -c conda-forge

echo "=== Building pymt_cfe ==="
conda mambabuild CFE/pymt_cfe/recipe -c local -c conda-forge

echo "=== Build complete ==="
echo "Packages are in: $(conda build --output CFE/conda-recipes/cfebmi 2>/dev/null || echo '<check conda build output>')"
