#!/usr/bin/env bash
set -euo pipefail

# Install pymt_topmodel from a local sdist tarball into the CURRENT active conda/pyenv env.
# Assumptions:
#   - This script and pymt_topmodel-*.tar.gz are in the same directory.
#   - TOPMODEL is already built somewhere on the system.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${CONDA_PREFIX:-}" ]]; then
  echo "ERROR: No active conda environment detected (CONDA_PREFIX is empty)." >&2
  echo "For pyenv, run this first:" >&2
  echo "  export CONDA_PREFIX=\$(pyenv prefix)" >&2
  echo "Then re-run this script." >&2
  exit 1
fi

PYTHON_BIN="${CONDA_PREFIX}/bin/python"
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "ERROR: Active environment does not contain an executable Python:" >&2
  echo "  ${PYTHON_BIN}" >&2
  echo "Activate your target env first, then run this script." >&2
  exit 1
fi

if ! "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
  echo "ERROR: pip is not available in the active env." >&2
  echo "Install pip in the env, then re-run." >&2
  exit 1
fi

# Prefer newest tarball if multiple are present.
mapfile -t TARBALLS < <(ls -1t "${SCRIPT_DIR}"/pymt_topmodel-*.tar.gz 2>/dev/null || true)
if [[ ${#TARBALLS[@]} -eq 0 ]]; then
  echo "ERROR: No pymt_topmodel-*.tar.gz found in ${SCRIPT_DIR}" >&2
  exit 1
fi
TARBALL="${TARBALLS[0]}"

# Source distributions must either include generated topmodel.c or contain a setup.py
# that explicitly cythonizes topmodel.pyx.
TARBALL_SETUP="$(tar -tzf "$TARBALL" | grep -E '^[^/]+/setup\.py$' | head -n1 || true)"
if ! tar -tzf "$TARBALL" | grep -Eq '/pymt_topmodel/lib/topmodel\.c$'; then
  if [[ -z "$TARBALL_SETUP" ]] || ! tar -xOf "$TARBALL" "$TARBALL_SETUP" | grep -q 'cythonize'; then
    echo "ERROR: Selected tarball is missing generated pymt_topmodel/lib/topmodel.c" >&2
    echo "and its setup.py does not explicitly run Cython." >&2
    echo >&2
    echo "Rebuild pymt_topmodel-*.tar.gz from the updated package sources, then re-run:" >&2
    echo "  cd /path/to/TOPMODEL/pymt_topmodel" >&2
    echo "  rm -rf build dist *.egg-info" >&2
    echo "  uv build" >&2
    echo >&2
    echo "Then copy the new dist/pymt_topmodel-*.tar.gz next to install.sh." >&2
    exit 1
  fi
fi

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# ─── Helper: full filesystem scan skipping virtual/system dirs ───────────────
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

# ─── Locate libtopmodelbmi.so ────────────────────────────────────────────────

pkg_config_include_dirs() {
  if have_cmd pkg-config && pkg-config --exists topmodelbmi 2>/dev/null; then
    pkg-config --cflags topmodelbmi 2>/dev/null | tr ' ' '\n' | sed -n 's/^-I//p'
  fi
}

pkg_config_library_dirs() {
  if have_cmd pkg-config && pkg-config --exists topmodelbmi 2>/dev/null; then
    pkg-config --libs-only-L topmodelbmi 2>/dev/null | tr ' ' '\n' | sed -n 's/^-L//p'
  fi
}

first_existing_libdir() {
  local d
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    if compgen -G "$d/libtopmodelbmi.so*" > /dev/null; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

TOPMODEL_LIB_DIR="${TOPMODEL_LIB_DIR:-}"

# 1) User-set env var.
if [[ -n "$TOPMODEL_LIB_DIR" ]] && compgen -G "$TOPMODEL_LIB_DIR/libtopmodelbmi.so*" > /dev/null 2>&1; then
  : # already good
else
  # 2) pkg-config.
  if TOPMODEL_LIB_DIR="$(pkg_config_library_dirs | first_existing_libdir 2>/dev/null || true)"; then
    :
  fi
fi

# 3) Search known roots.
if [[ -z "$TOPMODEL_LIB_DIR" ]]; then
  SEARCH_ROOTS=(
    "/workspace/topmodel"
    "/workspace/topmodel/build"
    "/workspace/topmodel/cmake_build"
    "$HOME/NextGenVS/ngen/extern/topmodel"
    "$HOME/NextGenVS/ngen/extern/topmodel/cmake_build"
    "$HOME/NextGenVS/ngen/extern/topmodel/topmodel"
    "/opt"
    "/usr/local"
    "/usr"
    "$HOME"
  )
  for root in "${SEARCH_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    hit="$(find "$root" -type f \
      \( -name 'libtopmodelbmi.so' -o -name 'libtopmodelbmi.so.*' \) \
      2>/dev/null | head -n1 || true)"
    if [[ -n "$hit" ]]; then
      TOPMODEL_LIB_DIR="$(dirname "$hit")"
      break
    fi
  done
fi

# 4) Full filesystem scan as last resort.
if [[ -z "$TOPMODEL_LIB_DIR" ]]; then
  hit="$(find_on_fs 'libtopmodelbmi.so' || true)"
  [[ -n "$hit" ]] && TOPMODEL_LIB_DIR="$(dirname "$hit")"
fi

if [[ -z "$TOPMODEL_LIB_DIR" ]]; then
  echo "ERROR: Could not locate libtopmodelbmi.so* on this system." >&2
  echo "Set TOPMODEL_LIB_DIR to the directory containing libtopmodelbmi.so and re-run:" >&2
  echo "  export TOPMODEL_LIB_DIR=/path/to/topmodel/build_or_cmake_build" >&2
  echo "  ./install.sh" >&2
  exit 1
fi

# ─── Locate TOPMODEL_ROOT for headers ────────────────────────────────────────

TOPMODEL_ROOT="${TOPMODEL_ROOT:-}"

if [[ -z "$TOPMODEL_ROOT" ]]; then
  for candidate in \
    "$(cd "$TOPMODEL_LIB_DIR/.." && pwd 2>/dev/null || true)" \
    "$(cd "$TOPMODEL_LIB_DIR/../topmodel" && pwd 2>/dev/null || true)" \
    "$(cd "$TOPMODEL_LIB_DIR/../.." && pwd 2>/dev/null || true)"; do
    [[ -n "$candidate" ]] || continue
    if [[ -f "$candidate/include/bmi_topmodel.h" && -f "$candidate/include/bmi.h" ]]; then
      TOPMODEL_ROOT="$candidate"
      break
    fi
  done
fi

# pkg-config include dirs.
if [[ -z "$TOPMODEL_ROOT" ]]; then
  while IFS= read -r inc; do
    [[ -n "$inc" ]] || continue
    if [[ -f "$inc/bmi_topmodel.h" && -f "$inc/bmi.h" ]]; then
      TOPMODEL_ROOT="$(cd "$inc/.." && pwd 2>/dev/null || true)"
      break
    fi
  done < <(pkg_config_include_dirs)
fi

# Search known source roots for include/bmi_topmodel.h.
if [[ -z "$TOPMODEL_ROOT" ]]; then
  for root in \
    "/workspace/topmodel" \
    "$HOME/NextGenVS/ngen/extern/topmodel/topmodel" \
    "$HOME/NextGenVS/ngen/extern/topmodel"; do
    [[ -d "$root" ]] || continue
    if [[ -f "$root/include/bmi_topmodel.h" && -f "$root/include/bmi.h" ]]; then
      TOPMODEL_ROOT="$root"
      break
    fi
  done
fi

# Full filesystem scan for bmi_topmodel.h.
if [[ -z "$TOPMODEL_ROOT" ]]; then
  header_hit="$(find_on_fs 'bmi_topmodel.h' || true)"
  if [[ -n "$header_hit" ]]; then
    maybe_root="$(cd "$(dirname "$header_hit")/.." && pwd 2>/dev/null || true)"
    if [[ -f "$maybe_root/include/bmi_topmodel.h" ]]; then
      TOPMODEL_ROOT="$maybe_root"
    fi
  fi
fi

if [[ -z "$TOPMODEL_ROOT" || ! -f "$TOPMODEL_ROOT/include/bmi_topmodel.h" || ! -f "$TOPMODEL_ROOT/include/bmi.h" ]]; then
  echo "ERROR: Could not determine TOPMODEL_ROOT containing include/bmi_topmodel.h and include/bmi.h" >&2
  echo "Found TOPMODEL_LIB_DIR=$TOPMODEL_LIB_DIR but no matching headers." >&2
  echo "Set TOPMODEL_ROOT manually and re-run:" >&2
  echo "  export TOPMODEL_ROOT=/path/to/topmodel" >&2
  echo "  ./install.sh" >&2
  exit 1
fi

export TOPMODEL_ROOT
export TOPMODEL_LIB_DIR
export TOPMODEL_INCLUDE_DIR="${TOPMODEL_ROOT}/include"
export LD_LIBRARY_PATH="${TOPMODEL_LIB_DIR}:${LD_LIBRARY_PATH:-}"

# ─── Ensure working C compiler ───────────────────────────────────────────────
_check_compiler() {
  command -v "$1" >/dev/null 2>&1 || return 1
  echo 'int main(){}' | "$1" -x c - -o /dev/null 2>/dev/null || return 1
}

_under_active_env() {
  [[ "$1" == "${CONDA_PREFIX}/bin/"* ]]
}

_matching_cxx() {
  local cc="$1"
  local cxx=""
  case "$cc" in
    *-conda-linux-gnu-cc) cxx="${cc%-cc}-c++" ;;
    *-conda-linux-gnu-gcc) cxx="${cc%-gcc}-g++" ;;
    */gcc) cxx="${cc%/gcc}/g++" ;;
    */cc) cxx="${cc%/cc}/c++" ;;
  esac
  [[ -n "$cxx" && -x "$cxx" ]] && echo "$cxx"
}

_select_conda_compiler() {
  local candidates=()
  local candidate

  [[ -n "${CC:-}" ]] && candidates+=("$CC")
  for candidate in \
    "${CONDA_PREFIX}"/bin/*-conda-linux-gnu-cc \
    "${CONDA_PREFIX}"/bin/*-conda-linux-gnu-gcc \
    "${CONDA_PREFIX}"/bin/gcc \
    "${CONDA_PREFIX}"/bin/cc; do
    [[ -x "$candidate" ]] && candidates+=("$candidate")
  done

  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    _under_active_env "$candidate" || continue
    if _check_compiler "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

if [[ -x /usr/bin/gcc ]] && _check_compiler /usr/bin/gcc; then
  export CC=/usr/bin/gcc
  [[ -x /usr/bin/g++ ]] && export CXX=/usr/bin/g++ || unset CXX 2>/dev/null || true
  export LDSHARED="/usr/bin/gcc -shared"
  unset _CONDA_PYTHON_SYSCONFIGDATA_NAME
  unset LDFLAGS CFLAGS CXXFLAGS LD AR NM RANLIB DEBUG_CFLAGS DEBUG_CXXFLAGS 2>/dev/null || true
  echo "  Using system CC: $CC"
elif CONDA_CC="$(_select_conda_compiler)"; then
  export CC="$CONDA_CC"
  CONDA_CXX="$(_matching_cxx "$CONDA_CC")"
  [[ -n "$CONDA_CXX" ]] && export CXX="$CONDA_CXX" || unset CXX 2>/dev/null || true
  export LDSHARED="${CC} -shared"
  echo "  Using active-env CC: $CC"
else
  echo "ERROR: No safe working C compiler found for this env." >&2
  echo "Install a compiler into the target env, then re-run." >&2
  exit 1
fi

# ─── Print detected paths ───────────────────────────────────────────────────

GCC_PATH="$(command -v gcc 2>/dev/null || true)"

echo "Using active env       : ${CONDA_PREFIX}"
echo "Using Python           : ${PYTHON_BIN}"
echo "Using tarball          : ${TARBALL}"
echo "Detected TOPMODEL_ROOT : ${TOPMODEL_ROOT}"
echo "Detected TOPMODEL_LIB_DIR: ${TOPMODEL_LIB_DIR}"
echo "gcc in PATH            : ${GCC_PATH:-<not found>}"
echo "Build CC               : ${CC:-<not set>}"

# ─── Ensure build dependencies are present ───────────────────────────────────
ensure_python_module() {
  local module_name="$1"
  local package_name="$2"

  "$PYTHON_BIN" -c "import ${module_name}" 2>/dev/null || {
    echo "  ${package_name} not found — installing..."
    "$PYTHON_BIN" -m pip install "${package_name}"
  }
}

echo "Checking build dependencies (numpy, Cython, setuptools, wheel)..."
ensure_python_module numpy numpy
ensure_python_module Cython cython
ensure_python_module setuptools setuptools
ensure_python_module wheel wheel

# ─── Install ─────────────────────────────────────────────────────────────────
"$PYTHON_BIN" -m pip install --no-build-isolation "$TARBALL"

# ─── Persist LD_LIBRARY_PATH for future conda env activations ────────────────

ACTIVATE_D="${CONDA_PREFIX}/etc/conda/activate.d"
DEACTIVATE_D="${CONDA_PREFIX}/etc/conda/deactivate.d"
mkdir -p "$ACTIVATE_D" "$DEACTIVATE_D"

cat > "${ACTIVATE_D}/pymt_topmodel.sh" <<EOF
#!/usr/bin/env bash
# Added by pymt_topmodel installer
if [[ ":\${LD_LIBRARY_PATH:-}:" != *":${TOPMODEL_LIB_DIR}:"* ]]; then
  export LD_LIBRARY_PATH="${TOPMODEL_LIB_DIR}:\${LD_LIBRARY_PATH:-}"
fi
EOF

cat > "${DEACTIVATE_D}/pymt_topmodel.sh" <<'EOF'
#!/usr/bin/env bash
# Intentionally no-op. We do not try to strip path segments on deactivate.
true
EOF

echo
echo "Install complete."
echo "A conda activation hook was written to: ${ACTIVATE_D}/pymt_topmodel.sh"
echo "Re-activate your env to ensure LD_LIBRARY_PATH is set in future shells:"
echo "  conda deactivate && conda activate ${CONDA_DEFAULT_ENV:-<your-env>}"
echo
echo "Quick test:"
echo "  ${PYTHON_BIN} -c \"from pymt_topmodel import TOPMODEL; print('pymt_topmodel OK')\""
