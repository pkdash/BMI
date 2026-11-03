#!/usr/bin/env bash
set -euo pipefail

# Install pymt_cfe from a local sdist tarball into the CURRENT active conda env.
# Assumptions:
#   - This script and pymt_cfe-*.tar.gz are in the same directory.
#   - CFE is already installed somewhere on the system.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${CONDA_PREFIX:-}" ]]; then
  echo "ERROR: No active conda environment detected (CONDA_PREFIX is empty)." >&2
  echo "Activate your target env first, then run this script." >&2
  exit 1
fi

PYTHON_BIN="${CONDA_PREFIX}/bin/python"
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "ERROR: Active conda env does not contain an executable Python:" >&2
  echo "  ${PYTHON_BIN}" >&2
  echo "Activate your target env first, then run this script." >&2
  exit 1
fi

if ! "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
  echo "ERROR: pip is not available in the active conda env." >&2
  echo "Install pip in the env, then re-run:" >&2
  echo "  conda install -n ${CONDA_DEFAULT_ENV:-<env-name>} pip" >&2
  exit 1
fi

# Prefer newest tarball if multiple are present.
mapfile -t TARBALLS < <(ls -1t "${SCRIPT_DIR}"/pymt_cfe-*.tar.gz 2>/dev/null || true)
if [[ ${#TARBALLS[@]} -eq 0 ]]; then
  echo "ERROR: No pymt_cfe-*.tar.gz found in ${SCRIPT_DIR}" >&2
  exit 1
fi
TARBALL="${TARBALLS[0]}"

# Source distributions must either include generated cfe.c or contain a setup.py
# that explicitly cythonizes cfe.pyx. Older tarballs excluded cfe.c but did not
# force cythonization, which fails later with:
#   cc1: fatal error: pymt_cfe/lib/cfe.c: No such file or directory
TARBALL_SETUP="$(tar -tzf "$TARBALL" | grep -E '^[^/]+/setup\.py$' | head -n1 || true)"
if ! tar -tzf "$TARBALL" | grep -Eq '/pymt_cfe/lib/cfe\.c$'; then
  if [[ -z "$TARBALL_SETUP" ]] || ! tar -xOf "$TARBALL" "$TARBALL_SETUP" | grep -q 'cythonize'; then
    echo "ERROR: Selected tarball is missing generated pymt_cfe/lib/cfe.c" >&2
    echo "and its setup.py does not explicitly run Cython." >&2
    echo >&2
    echo "Rebuild pymt_cfe-*.tar.gz from the updated package sources, then re-run:" >&2
    echo "  cd /path/to/CFE/pymt_cfe" >&2
    echo "  rm -rf build dist *.egg-info" >&2
    echo "  python -m build --sdist" >&2
    echo >&2
    echo "Then copy the new dist/pymt_cfe-*.tar.gz next to install.sh." >&2
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

# ─── Locate libcfebmi.so ──────────────────────────────────────────────────────

# Parse -I/-L flags from pkg-config if available.
pkg_config_include_dirs() {
  if have_cmd pkg-config && pkg-config --exists cfebmi 2>/dev/null; then
    pkg-config --cflags cfebmi 2>/dev/null | tr ' ' '\n' | sed -n 's/^-I//p'
  fi
}

pkg_config_library_dirs() {
  if have_cmd pkg-config && pkg-config --exists cfebmi 2>/dev/null; then
    pkg-config --libs-only-L cfebmi 2>/dev/null | tr ' ' '\n' | sed -n 's/^-L//p'
  fi
}

first_existing_libdir() {
  local d
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    if compgen -G "$d/libcfebmi.so*" > /dev/null; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

CFE_LIB_DIR="${CFE_LIB_DIR:-}"

# 1) User-set env var.
if [[ -n "$CFE_LIB_DIR" ]] && compgen -G "$CFE_LIB_DIR/libcfebmi.so*" > /dev/null 2>&1; then
  : # already good
else
  # 2) pkg-config.
  if CFE_LIB_DIR="$(pkg_config_library_dirs | first_existing_libdir 2>/dev/null || true)"; then
    :
  fi
fi

# 3) Search known roots (fast).
if [[ -z "$CFE_LIB_DIR" ]]; then
  SEARCH_ROOTS=(
    "/dmod/shared_libs"
    "/dmod"
    "/workspace/cfe"
    "/workspace/cfe/cmake_build"
    "/workspace/cfe/build"
    "/opt"
    "/usr/local"
    "/usr"
    "$HOME"
  )
  for root in "${SEARCH_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    hit="$(find "$root" -type f \
      \( -name 'libcfebmi.so' -o -name 'libcfebmi.so.*' \) \
      2>/dev/null | head -n1 || true)"
    if [[ -n "$hit" ]]; then
      CFE_LIB_DIR="$(dirname "$hit")"
      break
    fi
  done
fi

# 4) Full filesystem scan as last resort.
if [[ -z "$CFE_LIB_DIR" ]]; then
  hit="$(find_on_fs 'libcfebmi.so' || true)"
  [[ -n "$hit" ]] && CFE_LIB_DIR="$(dirname "$hit")"
fi

if [[ -z "$CFE_LIB_DIR" ]]; then
  echo "ERROR: Could not locate libcfebmi.so* on this system." >&2
  echo "Set CFE_LIB_DIR to the directory containing libcfebmi.so and re-run:" >&2
  echo "  export CFE_LIB_DIR=/path/to/cfe/cmake_build" >&2
  echo "  ./install.sh" >&2
  exit 1
fi

# ─── Locate CFE_ROOT (for headers) ───────────────────────────────────────────

CFE_ROOT="${CFE_ROOT:-}"

if [[ -z "$CFE_ROOT" ]]; then
  for candidate in \
    "$(cd "$CFE_LIB_DIR/.." && pwd 2>/dev/null || true)" \
    "$(cd "$CFE_LIB_DIR/../.." && pwd 2>/dev/null || true)"; do
    [[ -n "$candidate" ]] || continue
    if [[ -f "$candidate/bmi/bmi.h" ]]; then
      CFE_ROOT="$candidate"
      break
    fi
  done
fi

# pkg-config include dirs.
if [[ -z "$CFE_ROOT" ]]; then
  while IFS= read -r inc; do
    [[ -n "$inc" ]] || continue
    if [[ -f "$inc/bmi.h" ]]; then
      CFE_ROOT="$(cd "$inc/.." && pwd 2>/dev/null || true)"
      break
    fi
  done < <(pkg_config_include_dirs)
fi

# Full filesystem scan for bmi/bmi.h.
if [[ -z "$CFE_ROOT" ]]; then
  bmi_hit="$(find_on_fs 'bmi.h' || true)"
  if [[ -n "$bmi_hit" ]]; then
    CFE_ROOT="$(cd "$(dirname "$bmi_hit")/.." && pwd 2>/dev/null || true)"
  fi
fi

if [[ -z "$CFE_ROOT" || ! -f "$CFE_ROOT/bmi/bmi.h" ]]; then
  echo "ERROR: Could not determine CFE_ROOT containing bmi/bmi.h" >&2
  echo "Found CFE_LIB_DIR=$CFE_LIB_DIR but no matching headers." >&2
  echo "Set CFE_ROOT manually and re-run:" >&2
  echo "  export CFE_ROOT=/path/to/cfe" >&2
  echo "  ./install.sh" >&2
  exit 1
fi

export CFE_ROOT
export CFE_LIB_DIR
export LD_LIBRARY_PATH="${CFE_LIB_DIR}:${LD_LIBRARY_PATH:-}"

# ─── Ensure working C compiler ───────────────────────────────────────────────
# Prefer system gcc when available. Otherwise use only a compiler from the
# active conda env. JupyterHub images often have another env, such as
# /srv/conda/envs/notebook, earlier on PATH; mixing that gcc with this env's
# compiler_compat/ld commonly fails with: cannot find -lgcc.

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
  # Unset conda compiler overrides so distutils/setuptools uses system toolchain.
  # _CONDA_PYTHON_SYSCONFIGDATA_NAME controls which sysconfigdata Python uses
  # for build config — if set, it points to a file with conda compiler paths
  # baked in, overriding CC/LDSHARED. Unsetting forces Python's default.
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
  echo "ERROR: No safe working C compiler found for this conda env." >&2
  echo >&2
  echo "The active gcc on PATH is: $(command -v gcc 2>/dev/null || echo '<not found>')" >&2
  echo "This installer will not use gcc from another conda env because that" >&2
  echo "can fail at link time with: cannot find -lgcc" >&2
  echo >&2
  echo "Install a compiler into the target env, then re-run:" >&2
  echo "  conda install -c conda-forge compilers libgcc-ng libstdcxx-ng" >&2
  echo >&2
  echo "If your site prefers explicit Linux compiler packages, use:" >&2
  echo "  conda install -c conda-forge gcc_linux-64 gxx_linux-64 libgcc-ng libstdcxx-ng" >&2
  exit 1
fi

# ─── Print detected paths ───────────────────────────────────────────────────

GCC_PATH="$(command -v gcc 2>/dev/null || true)"

echo "Using active conda env : ${CONDA_PREFIX}"
echo "Using Python           : ${PYTHON_BIN}"
echo "Using tarball          : ${TARBALL}"
echo "Detected CFE_ROOT      : ${CFE_ROOT}"
echo "Detected CFE_LIB_DIR   : ${CFE_LIB_DIR}"
echo "gcc in PATH            : ${GCC_PATH:-<not found>}"
echo "Build CC               : ${CC:-<not set>}"

# ─── Ensure build dependencies are present ───────────────────────────────────
# --no-build-isolation means the build uses the current env directly, so build
# dependencies from pyproject.toml must already be importable in this env.
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
# --no-build-isolation ensures the build subprocess inherits exported env vars
# (CC, LDSHARED, CFE_ROOT, CFE_LIB_DIR) needed to find .so and headers.
"$PYTHON_BIN" -m pip install --no-build-isolation "$TARBALL"

# ─── Persist LD_LIBRARY_PATH for future conda env activations ────────────────

ACTIVATE_D="${CONDA_PREFIX}/etc/conda/activate.d"
DEACTIVATE_D="${CONDA_PREFIX}/etc/conda/deactivate.d"
mkdir -p "$ACTIVATE_D" "$DEACTIVATE_D"

cat > "${ACTIVATE_D}/pymt_cfe.sh" <<EOF
#!/usr/bin/env bash
# Added by pymt_cfe installer
if [[ ":\${LD_LIBRARY_PATH:-}:" != *":${CFE_LIB_DIR}:"* ]]; then
  export LD_LIBRARY_PATH="${CFE_LIB_DIR}:\${LD_LIBRARY_PATH:-}"
fi
EOF

cat > "${DEACTIVATE_D}/pymt_cfe.sh" <<'EOF'
#!/usr/bin/env bash
# Intentionally no-op. We do not try to strip path segments on deactivate.
true
EOF

echo
echo "Install complete."
echo "A conda activation hook was written to: ${ACTIVATE_D}/pymt_cfe.sh"
echo "Re-activate your env to ensure LD_LIBRARY_PATH is set in future shells:"
echo "  conda deactivate && conda activate ${CONDA_DEFAULT_ENV:-<your-env>}"
echo
echo "Quick test:"
echo "  ${PYTHON_BIN} -c \"from pymt_cfe import CFE; print('pymt_cfe OK')\""
