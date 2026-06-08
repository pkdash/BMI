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

# Prefer newest tarball if multiple are present.
mapfile -t TARBALLS < <(ls -1t "${SCRIPT_DIR}"/pymt_cfe-*.tar.gz 2>/dev/null || true)
if [[ ${#TARBALLS[@]} -eq 0 ]]; then
  echo "ERROR: No pymt_cfe-*.tar.gz found in ${SCRIPT_DIR}" >&2
  exit 1
fi
TARBALL="${TARBALLS[0]}"

have_cmd() { command -v "$1" >/dev/null 2>&1; }

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

# 1) Try pkg-config for library dir
CFE_LIB_DIR=""
if CFE_LIB_DIR="$(pkg_config_library_dirs | first_existing_libdir || true)"; then
  :
fi

# 2) Fallback: search common install roots for libcfebmi
if [[ -z "$CFE_LIB_DIR" ]]; then
  SEARCH_ROOTS=(
    "/opt"
    "/usr/local"
    "/usr"
    "$HOME"
  )
  for root in "${SEARCH_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    hit="$(find "$root" -type f \( -name 'libcfebmi.so' -o -name 'libcfebmi.so.*' \) 2>/dev/null | head -n1 || true)"
    if [[ -n "$hit" ]]; then
      CFE_LIB_DIR="$(dirname "$hit")"
      break
    fi
  done
fi

if [[ -z "$CFE_LIB_DIR" ]]; then
  echo "ERROR: Could not locate libcfebmi.so* on this system." >&2
  echo "Install CFE first, or set CFE_LIB_DIR manually and re-run." >&2
  exit 1
fi

# Determine CFE_ROOT using lib dir heuristics first.
CFE_ROOT=""
for candidate in \
  "$(cd "$CFE_LIB_DIR/.." && pwd 2>/dev/null || true)" \
  "$(cd "$CFE_LIB_DIR/../.." && pwd 2>/dev/null || true)"; do
  [[ -n "$candidate" ]] || continue
  if [[ -f "$candidate/bmi/bmi.h" ]]; then
    CFE_ROOT="$candidate"
    break
  fi
done

# Fallback: use pkg-config include dirs, then search for bmi.h.
if [[ -z "$CFE_ROOT" ]]; then
  while IFS= read -r inc; do
    [[ -n "$inc" ]] || continue
    if [[ -f "$inc/bmi.h" ]]; then
      CFE_ROOT="$(cd "$inc/.." && pwd 2>/dev/null || true)"
      break
    fi
  done < <(pkg_config_include_dirs)
fi

if [[ -z "$CFE_ROOT" ]]; then
  bmi_hit="$(find /opt /usr/local /usr "$HOME" -type f -path '*/bmi/bmi.h' 2>/dev/null | head -n1 || true)"
  if [[ -n "$bmi_hit" ]]; then
    CFE_ROOT="$(cd "$(dirname "$bmi_hit")/.." && pwd 2>/dev/null || true)"
  fi
fi

if [[ -z "$CFE_ROOT" || ! -f "$CFE_ROOT/bmi/bmi.h" ]]; then
  echo "ERROR: Could not determine CFE_ROOT containing bmi/bmi.h" >&2
  echo "Found CFE_LIB_DIR=$CFE_LIB_DIR but no matching headers." >&2
  exit 1
fi

export CFE_ROOT
export CFE_LIB_DIR

# Optionally use system compiler if available (helps in some conda toolchain setups).
if [[ -x /usr/bin/gcc ]]; then export CC=/usr/bin/gcc; fi
if [[ -x /usr/bin/g++ ]]; then export CXX=/usr/bin/g++; fi

# Ensure runtime linker can find libcfebmi for this process now.
export LD_LIBRARY_PATH="${CFE_LIB_DIR}:${LD_LIBRARY_PATH:-}"

echo "Using active conda env: ${CONDA_PREFIX}"
echo "Using tarball: ${TARBALL}"
echo "Detected CFE_ROOT: ${CFE_ROOT}"
echo "Detected CFE_LIB_DIR: ${CFE_LIB_DIR}"

# Install with uv if available, otherwise pip.
if have_cmd uv; then
  uv pip install "$TARBALL"
else
  python -m pip install "$TARBALL"
fi

# Persist LD_LIBRARY_PATH for future activations of this conda env.
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

echo "Quick test:"
echo "  python -c \"from pymt_cfe import CFE; print('pymt_cfe OK')\""
