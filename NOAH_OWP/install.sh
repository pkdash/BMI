#!/usr/bin/env bash
set -euo pipefail

# Install pymt_noah_owp from a local sdist tarball into the CURRENT active conda env.
# Assumptions:
#   - This script and pymt_noah_owp-*.tar.gz are in the same directory.
#   - Noah-OWP-Modular is already installed/built somewhere on the system,
#     and libsurfacebmi.so is available.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${CONDA_PREFIX:-}" ]]; then
  echo "ERROR: No active conda environment detected (CONDA_PREFIX is empty)." >&2
  echo "Activate your target env first, then run this script." >&2
  exit 1
fi

# Prefer newest tarball if multiple are present.
mapfile -t TARBALLS < <(ls -1t "${SCRIPT_DIR}"/pymt_noah_owp-*.tar.gz 2>/dev/null || true)
if [[ ${#TARBALLS[@]} -eq 0 ]]; then
  echo "ERROR: No pymt_noah_owp-*.tar.gz found in ${SCRIPT_DIR}" >&2
  exit 1
fi
TARBALL="${TARBALLS[0]}"

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# ─── Helper: search for a file across the full filesystem ────────────────────
# Skips virtual/system directories that will never contain model installs.
find_on_fs() {
  local filename="$1"
  for root in /*; do
    [[ -d "$root" ]] || continue
    case "$root" in /proc|/sys|/dev|/run|/tmp) continue ;; esac
    local hit
    hit="$(find "$root" -type f -name "$filename" 2>/dev/null | head -n1 || true)"
    if [[ -n "$hit" ]]; then
      echo "$hit"
      return 0
    fi
  done
  return 1
}

# ─── Locate libsurfacebmi.so ──────────────────────────────────────────────────

NOAH_LIB_DIR="${NOAH_LIB_DIR:-}"

if [[ -n "$NOAH_LIB_DIR" ]] && compgen -G "$NOAH_LIB_DIR/libsurfacebmi.so*" > /dev/null 2>&1; then
  : # already good — user set it explicitly
else
  # Search known roots first (fast), then fall back to full filesystem scan.
  SEARCH_ROOTS=(
    "/workspace/noah-owp-modular"
    "/workspace/noah-owp-modular/cmake_build"
    "/dmod/shared_libs"
    "/dmod"
    "/opt"
    "/usr/local"
    "/usr"
    "$HOME"
  )
  for root in "${SEARCH_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    hit="$(find "$root" -type f \
      \( -name 'libsurfacebmi.so' -o -name 'libsurfacebmi.so.*' \) \
      2>/dev/null | head -n1 || true)"
    if [[ -n "$hit" ]]; then
      NOAH_LIB_DIR="$(dirname "$hit")"
      break
    fi
  done

  # Full filesystem scan as last resort.
  if [[ -z "$NOAH_LIB_DIR" ]]; then
    hit="$(find_on_fs 'libsurfacebmi.so' || true)"
    [[ -n "$hit" ]] && NOAH_LIB_DIR="$(dirname "$hit")"
  fi
fi

if [[ -z "$NOAH_LIB_DIR" ]]; then
  echo "ERROR: Could not locate libsurfacebmi.so* on this system." >&2
  echo "Set NOAH_LIB_DIR to the directory containing libsurfacebmi.so and re-run:" >&2
  echo "  export NOAH_LIB_DIR=/path/to/noah-owp-modular/cmake_build" >&2
  echo "  ./install.sh" >&2
  exit 1
fi

# ─── Locate Noah-OWP source root ─────────────────────────────────────────────

NOAH_ROOT="${NOAH_ROOT:-}"

if [[ -z "$NOAH_ROOT" ]]; then
  for candidate in \
    "$(cd "$NOAH_LIB_DIR" && pwd 2>/dev/null || true)" \
    "$(cd "$NOAH_LIB_DIR/.." && pwd 2>/dev/null || true)" \
    "$(cd "$NOAH_LIB_DIR/../.." && pwd 2>/dev/null || true)"; do
    [[ -n "$candidate" ]] || continue
    if [[ -f "$candidate/bmi/bmi.f90" ]]; then
      NOAH_ROOT="$candidate"
      break
    fi
  done
fi

if [[ -z "$NOAH_ROOT" ]]; then
  hit="$(find_on_fs 'bmi_noahowp.f90' || true)"
  [[ -n "$hit" ]] && NOAH_ROOT="$(cd "$(dirname "$hit")/.." && pwd 2>/dev/null || true)"
fi

if [[ -z "$NOAH_ROOT" ]]; then
  echo "WARNING: Could not determine NOAH_ROOT." >&2
  echo "If the build fails, set it manually:" >&2
  echo "  export NOAH_ROOT=/path/to/noah-owp-modular" >&2
fi

# ─── Locate .mod files (bmif_2_0.mod, bminoahowp.mod) ────────────────────────

NOAH_BMI_DIR="${NOAH_BMI_DIR:-}"

if [[ -z "$NOAH_BMI_DIR" ]]; then
  for candidate in \
    "${NOAH_LIB_DIR}/mod" \
    "${NOAH_ROOT}/cmake_build/mod" \
    "${NOAH_ROOT}/bmi" \
    "${NOAH_LIB_DIR}"; do
    [[ -n "$candidate" ]] || continue
    if [[ -f "$candidate/bmif_2_0.mod" ]]; then
      NOAH_BMI_DIR="$candidate"
      break
    fi
  done
fi

if [[ -z "$NOAH_BMI_DIR" ]]; then
  hit="$(find_on_fs 'bmif_2_0.mod' || true)"
  [[ -n "$hit" ]] && NOAH_BMI_DIR="$(dirname "$hit")"
fi

if [[ -z "$NOAH_BMI_DIR" ]]; then
  echo "ERROR: Could not locate bmif_2_0.mod (Noah Fortran module files)." >&2
  echo "Set NOAH_BMI_DIR to the directory containing bmif_2_0.mod and re-run:" >&2
  echo "  For cmake builds: export NOAH_BMI_DIR=/path/to/noah-owp-modular/cmake_build/mod" >&2
  echo "  For make builds:  export NOAH_BMI_DIR=/path/to/noah-owp-modular/bmi" >&2
  echo "  ./install.sh" >&2
  exit 1
fi

# ─── Locate NetCDF Fortran library ───────────────────────────────────────────

NETCDF_LIB_DIR="${NETCDF:-/opt/conda}/lib"
if [[ ! -d "$NETCDF_LIB_DIR" ]]; then
  NETCDF_LIB_DIR="${CONDA_PREFIX}/lib"
fi

export NOAH_ROOT
export NOAH_LIB_DIR
export NOAH_BMI_DIR
export LD_LIBRARY_PATH="${NOAH_LIB_DIR}:${NETCDF_LIB_DIR}:${LD_LIBRARY_PATH:-}"

# ─── Ensure working C compiler ───────────────────────────────────────────────

_check_compiler() {
  command -v "$1" >/dev/null 2>&1 || return 1
  echo 'int main(){}' | "$1" -x c - -o /dev/null 2>/dev/null || return 1
}

if ! _check_compiler "${CC:-gcc}"; then
  if _check_compiler /usr/bin/gcc; then
    export CC=/usr/bin/gcc
    echo "  Using system CC: $CC"
  else
    echo "WARNING: No working C compiler found. Install gcc:" >&2
    echo "  conda install -c conda-forge gcc" >&2
  fi
fi

# ─── Ensure Fortran compiler ─────────────────────────────────────────────────

_find_gfortran() {
  local candidates=(
    "${FC:-}"
    gfortran
    /usr/bin/gfortran
    /usr/local/bin/gfortran
    "${CONDA_PREFIX}/bin/gfortran"
  )
  for c in "${candidates[@]}"; do
    [[ -n "$c" ]] || continue
    command -v "$c" >/dev/null 2>&1 && echo "$c" && return 0
  done
  local hit
  hit="$(find /usr /opt "${CONDA_PREFIX}" -name 'gfortran' -type f 2>/dev/null | head -n1 || true)"
  [[ -n "$hit" ]] && echo "$hit" && return 0
  # Full filesystem scan as last resort.
  hit="$(find_on_fs 'gfortran' || true)"
  [[ -n "$hit" ]] && echo "$hit" && return 0
  return 1
}

FC_PATH="$(_find_gfortran || true)"
if [[ -n "$FC_PATH" ]]; then
  export FC="$FC_PATH"
  echo "  Using Fortran compiler: $FC"
else
  echo "  gfortran not found — installing via conda..."
  if have_cmd conda; then
    conda install -y -c conda-forge gfortran
  elif have_cmd micromamba; then
    micromamba install -y -c conda-forge gfortran
  else
    echo "ERROR: No Fortran compiler found and cannot install automatically." >&2
    echo "Install gfortran manually and re-run:" >&2
    echo "  conda install -c conda-forge gfortran" >&2
    exit 1
  fi
  FC_PATH="$(_find_gfortran || true)"
  [[ -n "$FC_PATH" ]] && export FC="$FC_PATH"
fi

# ─── Print detected paths ────────────────────────────────────────────────────

echo "Using active conda env : ${CONDA_PREFIX}"
echo "Using tarball          : ${TARBALL}"
echo "Detected NOAH_LIB_DIR  : ${NOAH_LIB_DIR}"
echo "Detected NOAH_ROOT     : ${NOAH_ROOT:-<not found>}"
echo "Detected NOAH_BMI_DIR  : ${NOAH_BMI_DIR}"
echo "NetCDF lib dir         : ${NETCDF_LIB_DIR}"
echo "Fortran compiler       : ${FC:-<not set>}"

# ─── Ensure build dependencies are present ───────────────────────────────────

echo "Checking build dependencies (numpy, cython)..."
python -c "import numpy" 2>/dev/null || {
  echo "  numpy not found — installing..."
  python -m pip install numpy
}
python -c "import Cython" 2>/dev/null || {
  echo "  cython not found — installing..."
  python -m pip install cython
}

# ─── Install ─────────────────────────────────────────────────────────────────

if have_cmd uv; then
  uv pip install --no-build-isolation "$TARBALL"
else
  python -m pip install --no-build-isolation "$TARBALL"
fi

# ─── Persist LD_LIBRARY_PATH for future conda env activations ────────────────

ACTIVATE_D="${CONDA_PREFIX}/etc/conda/activate.d"
DEACTIVATE_D="${CONDA_PREFIX}/etc/conda/deactivate.d"
mkdir -p "$ACTIVATE_D" "$DEACTIVATE_D"

cat > "${ACTIVATE_D}/pymt_noah_owp.sh" <<EOF
#!/usr/bin/env bash
# Added by pymt_noah_owp installer
if [[ ":\${LD_LIBRARY_PATH:-}:" != *":${NOAH_LIB_DIR}:"* ]]; then
  export LD_LIBRARY_PATH="${NOAH_LIB_DIR}:\${LD_LIBRARY_PATH:-}"
fi
if [[ ":\${LD_LIBRARY_PATH:-}:" != *":${NETCDF_LIB_DIR}:"* ]]; then
  export LD_LIBRARY_PATH="${NETCDF_LIB_DIR}:\${LD_LIBRARY_PATH:-}"
fi
EOF

cat > "${DEACTIVATE_D}/pymt_noah_owp.sh" <<'EOF'
#!/usr/bin/env bash
# Intentionally no-op. We do not try to strip path segments on deactivate.
true
EOF

echo
echo "Install complete."
echo "A conda activation hook was written to: ${ACTIVATE_D}/pymt_noah_owp.sh"
echo "Re-activate your env to ensure LD_LIBRARY_PATH is set in future shells:"
echo "  conda deactivate && conda activate ${CONDA_DEFAULT_ENV:-<your-env>}"
echo
echo "Quick test:"
echo "  python -c \"from pymt_noah_owp import NOAH_OWP; print('pymt_noah_owp OK')\""
