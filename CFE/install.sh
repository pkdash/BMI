#!/usr/bin/env bash
set -euo pipefail

# Install pymt_cfe into a target Python environment (virtualenv OR conda).
#
# Usage:
#   ./install.sh [--python /path/to/python] [--source-tree | --tarball FILE]
#
# Interpreter selection, in order of precedence:
#   1. --python <path>   an explicit interpreter
#   2. $VIRTUAL_ENV      an activated virtualenv / venv
#   3. $CONDA_PREFIX     an activated conda env
#
# Install source:
#   --source-tree    build and install from ./pymt_cfe in this checkout
#   --tarball FILE   install the named sdist
#   (default)        newest pymt_cfe-*.tar.gz beside this script; falls back to
#                    the source tree when no tarball is present
#
# Assumptions:
#   - CFE is already built somewhere on this system. Export CFE_LIB_DIR to the
#     directory holding libcfebmi.so to skip the (slow) filesystem search, and
#     CFE_ROOT to the CFE source root holding bmi/bmi.h. For an ngen checkout
#     those are <ngen>/extern/cfe/cmake_build and <ngen>/extern/cfe/cfe.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_TREE="${SCRIPT_DIR}/pymt_cfe"

PYTHON_OVERRIDE=""
INSTALL_MODE=""
TARBALL=""

usage() {
  sed -n '4,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --python)      PYTHON_OVERRIDE="${2:-}"; shift 2 ;;
    --python=*)    PYTHON_OVERRIDE="${1#*=}"; shift ;;
    --source-tree) INSTALL_MODE="source"; shift ;;
    --tarball)     INSTALL_MODE="tarball"; TARBALL="${2:-}"; shift 2 ;;
    --tarball=*)   INSTALL_MODE="tarball"; TARBALL="${1#*=}"; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ─── Resolve the target interpreter ──────────────────────────────────────────

ENV_LABEL=""
if [[ -n "$PYTHON_OVERRIDE" ]]; then
  PYTHON_BIN="$PYTHON_OVERRIDE"
  ENV_LABEL="explicit --python"
elif [[ -n "${VIRTUAL_ENV:-}" ]]; then
  PYTHON_BIN="${VIRTUAL_ENV}/bin/python"
  ENV_LABEL="virtualenv ${VIRTUAL_ENV}"
elif [[ -n "${CONDA_PREFIX:-}" ]]; then
  PYTHON_BIN="${CONDA_PREFIX}/bin/python"
  ENV_LABEL="conda env ${CONDA_PREFIX}"
else
  echo "ERROR: No target Python environment detected." >&2
  echo "Activate a virtualenv (VIRTUAL_ENV) or conda env (CONDA_PREFIX)," >&2
  echo "or pass one explicitly:" >&2
  echo "  ./install.sh --python /path/to/venv/bin/python" >&2
  exit 1
fi

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "ERROR: Not an executable Python interpreter:" >&2
  echo "  ${PYTHON_BIN}" >&2
  echo "Activate your target environment first, or pass --python explicitly." >&2
  exit 1
fi

if ! "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
  echo "ERROR: pip is not available for ${PYTHON_BIN}." >&2
  if [[ -n "${CONDA_PREFIX:-}" && -z "${VIRTUAL_ENV:-}" ]]; then
    echo "  conda install -n ${CONDA_DEFAULT_ENV:-<env-name>} pip" >&2
  else
    echo "  ${PYTHON_BIN} -m ensurepip --upgrade" >&2
  fi
  exit 1
fi

# ─── Resolve what to install ─────────────────────────────────────────────────

if [[ -z "$INSTALL_MODE" ]]; then
  # Portable stand-in for `mapfile -t`, which is a bash 4+ builtin and so is
  # unavailable under the bash 3.2 that ships with macOS.
  TARBALLS=()
  while IFS= read -r _tarball; do
    [[ -n "$_tarball" ]] && TARBALLS+=("$_tarball")
  done < <(ls -1t "${SCRIPT_DIR}"/pymt_cfe-*.tar.gz 2>/dev/null || true)
  if [[ ${#TARBALLS[@]} -gt 0 ]]; then
    INSTALL_MODE="tarball"
    TARBALL="${TARBALLS[0]}"   # newest wins
  elif [[ -f "${SOURCE_TREE}/setup.py" ]]; then
    INSTALL_MODE="source"
  else
    echo "ERROR: Nothing to install." >&2
    echo "No pymt_cfe-*.tar.gz in ${SCRIPT_DIR} and no setup.py in ${SOURCE_TREE}." >&2
    exit 1
  fi
fi

if [[ "$INSTALL_MODE" == "source" ]]; then
  if [[ ! -f "${SOURCE_TREE}/setup.py" ]]; then
    echo "ERROR: --source-tree requested but ${SOURCE_TREE}/setup.py does not exist." >&2
    exit 1
  fi
  INSTALL_TARGET="$SOURCE_TREE"
else
  if [[ ! -f "$TARBALL" ]]; then
    echo "ERROR: Tarball not found: ${TARBALL}" >&2
    exit 1
  fi
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
  INSTALL_TARGET="$TARBALL"
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
  [[ -n "${CONDA_PREFIX:-}" && "$1" == "${CONDA_PREFIX}/bin/"* ]]
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
elif [[ -n "${CONDA_PREFIX:-}" ]] && CONDA_CC="$(_select_conda_compiler)"; then
  export CC="$CONDA_CC"
  CONDA_CXX="$(_matching_cxx "$CONDA_CC")"
  [[ -n "$CONDA_CXX" ]] && export CXX="$CONDA_CXX" || unset CXX 2>/dev/null || true
  export LDSHARED="${CC} -shared"
  echo "  Using active-env CC: $CC"
else
  echo "ERROR: No usable C compiler found." >&2
  echo >&2
  echo "The active gcc on PATH is: $(command -v gcc 2>/dev/null || echo '<not found>')" >&2
  if [[ -n "${CONDA_PREFIX:-}" ]]; then
    echo "This installer will not use gcc from another conda env because that" >&2
    echo "can fail at link time with: cannot find -lgcc" >&2
    echo >&2
    echo "Install a compiler into the target env, then re-run:" >&2
    echo "  conda install -c conda-forge compilers libgcc-ng libstdcxx-ng" >&2
    echo >&2
    echo "If your site prefers explicit Linux compiler packages, use:" >&2
    echo "  conda install -c conda-forge gcc_linux-64 gxx_linux-64 libgcc-ng libstdcxx-ng" >&2
  else
    echo "pymt_cfe is a C extension, so a working compiler is required." >&2
    echo "On Debian/Ubuntu:  apt-get install build-essential" >&2
    echo "On RHEL/CentOS:    dnf groupinstall 'Development Tools'" >&2
  fi
  exit 1
fi

# ─── Print detected paths ───────────────────────────────────────────────────

GCC_PATH="$(command -v gcc 2>/dev/null || true)"

echo "Target environment     : ${ENV_LABEL}"
echo "Using Python           : ${PYTHON_BIN}"
echo "Install source         : ${INSTALL_TARGET}"
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

# numpy is special-cased. With --no-build-isolation the numpy pin in
# pyproject.toml's [build-system] is bypassed entirely -- the build uses
# whatever numpy is already importable here. Installing an unconstrained
# "numpy" would therefore silently build against numpy 2 even though the pin
# says otherwise, which breaks consumers (notably NOAA-OWP/ngen) that require
# numpy<2 at runtime.
if "$PYTHON_BIN" -c "import numpy" 2>/dev/null; then
  NUMPY_VERSION="$("$PYTHON_BIN" -c "import numpy; print(numpy.__version__)")"
  NUMPY_MAJOR="${NUMPY_VERSION%%.*}"
  if [[ "$NUMPY_MAJOR" -ge 2 ]]; then
    echo "  WARNING: numpy ${NUMPY_VERSION} is installed in the target environment." >&2
    echo "  pymt_cfe will be built against it. Consumers pinned to numpy<2" >&2
    echo "  (such as ngen) will not be able to import the result." >&2
    echo "  To build for those, downgrade first:" >&2
    echo "    ${PYTHON_BIN} -m pip install 'numpy<2'" >&2
  else
    echo "  numpy ${NUMPY_VERSION} (ok)"
  fi
else
  echo "  numpy not found — installing numpy<2..."
  "$PYTHON_BIN" -m pip install "numpy<2"
fi

ensure_python_module Cython cython
ensure_python_module setuptools setuptools
ensure_python_module wheel wheel

# ─── Install ─────────────────────────────────────────────────────────────────
# --no-build-isolation ensures the build subprocess inherits exported env vars
# (CC, LDSHARED, CFE_ROOT, CFE_LIB_DIR) needed to find .so and headers.
"$PYTHON_BIN" -m pip install --no-build-isolation "$INSTALL_TARGET"

# ─── Done ────────────────────────────────────────────────────────────────────
# No activation hook is written. setup.py embeds the discovered library
# directories in the extension as an RPATH, so the installed module resolves
# libcfebmi without LD_LIBRARY_PATH being set in future shells. If the CFE build
# directory is later moved, reinstall rather than patching the environment.

echo
echo "Install complete."
echo
echo "Quick test:"
echo "  ${PYTHON_BIN} -c \"from pymt_cfe import CFE; print('pymt_cfe OK')\""
