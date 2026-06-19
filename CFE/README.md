# CFE + Babelizer + `pymt_cfe` Packaging Workflow

This repository provides a Docker-based workflow to:

1. Build NOAA-OWP CFE (`NGEN` mode)
2. Generate a Python BMI wrapper (`pymt_cfe`) with Babelizer
3. Test the wrapper in-container
4. Build distributable artifacts (`.tar.gz`, wheel) with `uv`
5. Install from the built tarball

---

## Repository layout

```text
CFE/
├── README.md
├── QUICKSTART.md
├── Dockerfile
├── babel.toml
├── regen_and_build.sh
├── post_babelize_patch.sh
├── install.sh
└── pymt_cfe/          # generated + patched Python wrapper package
```

---

## Prerequisites

- Docker installed and running
- This repository checked out locally
- Run commands from this `CFE` folder

## Environment recommendation

For local testing/installation outside Docker, install `pymt_cfe` in an isolated environment (recommended):

- Conda env, or
- Python virtual environment (`venv`)

This prevents dependency conflicts with your base environment and makes troubleshooting much easier.

Example with `venv`:

```bash
python -m venv .venv-pymt-cfe
source .venv-pymt-cfe/bin/activate
python -m pip install --upgrade pip
```

Example with conda:

```bash
conda create -n pymt-cfe python=3.11 -y
conda activate pymt-cfe
```

---

## 1) Build the Docker image

Use image name **`cfe-babelizer`**:

```bash
docker build --pull --no-cache -t cfe-babelizer .
```

> `--no-cache` is recommended when troubleshooting dependency/build changes.

---

## 2) Run the container (mount current folder)

Mount the current host folder into the container at `/workspace/user`:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  cfe-babelizer
```

Notes:
- CFE is already cloned and built inside the image at `/workspace/cfe`.
- `LD_LIBRARY_PATH` is set in the image to `/workspace/cfe/build`.

---

## 3) Generate the CFE BMI Python module with Babelizer

Inside the container:

```bash
# from /workspace/user
babelize init babel.toml
```

This generates/updates the `pymt_cfe/` package scaffold.

### Reapply local custom patches after regeneration

Babelizer can overwrite custom files. Use:

```bash
./post_babelize_patch.sh
```

This reapplies:
- `pymt_cfe/pymt_cfe/__init__.py` (`importlib.metadata` version handling)
- `pymt_cfe/setup.py` (portable CFE path discovery)

### One-shot regenerate + patch + build

Optional cleanup before regeneration (recommended while iterating):

```bash
# from /workspace/user
python -m pip uninstall -y pymt_cfe || true
rm -rf pymt_cfe/build pymt_cfe/dist pymt_cfe/*.egg-info
find pymt_cfe -type d -name "__pycache__" -prune -exec rm -rf {} +
find pymt_cfe -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete
```

Then run:

```bash
./regen_and_build.sh
```

---

## 4) Test `pymt_cfe` in the container

Install editable (from generated package folder):

```bash
cd /workspace/user/pymt_cfe
python -m pip install -e . --no-build-isolation
```

Quick import test:

```bash
python -c "from pymt_cfe import CFE; print('pymt_cfe import OK')"
python -c "from pymt_cfe.lib import CFE; m=CFE(); print(m.get_component_name())"
```

If needed, verify the extension and linked libraries:

```bash
python -c "import pymt_cfe.lib.cfe as m; print(m.__file__)"
ldd $(python -c "import pymt_cfe.lib.cfe as m; print(m.__file__)")
```

---

## 5) Build distributable package files (`tar.gz` and wheel)

Inside `pymt_cfe/`:

```bash
cd /workspace/user/pymt_cfe
rm -rf build dist *.egg-info
uv build
```

Artifacts are created in:

```text
/workspace/user/pymt_cfe/dist/
```

Optional checks:

```bash
uvx twine check dist/*
```

---

## 6) Install using built `.tar.gz`

### In a target environment (example)

Direct install may work if CFE paths are auto-detected. If not, set CFE paths explicitly first.

```bash
# Recommended explicit setup for direct install
export CFE_ROOT=/path/to/cfe
export CFE_LIB_DIR=/path/to/cfe/build   # directory containing libcfebmi.so*
export LD_LIBRARY_PATH="$CFE_LIB_DIR:$LD_LIBRARY_PATH"

uv pip install /path/to/pymt_cfe-0.1.tar.gz
```

If `uv` is not available:

```bash
python -m pip install /path/to/pymt_cfe-0.1.tar.gz
```

### Helper installer script (recommended)

This repo includes `install.sh` (same directory as tarball) that:
- Detects active conda env
- Finds CFE paths programmatically
- Sets required env vars for installation
- Installs tarball with the active env's `python -m pip`
- Avoids mixed JupyterHub conda compiler/linker setups
- Writes conda activation hook to set `LD_LIBRARY_PATH`

Use this script to avoid manual path exports where possible.

Usage:

```bash
chmod +x install.sh
./install.sh
```

---

## Architecture note (important)

Wheels are platform-specific. Example:
- wheel built on `aarch64` will not install on `x86_64`

For cross-platform testing, prefer installing the source distribution (`.tar.gz`) on the target machine, or build wheels on matching architecture.

---

## Suggested release checklist

1. `babelize init babel.toml`
2. `./post_babelize_patch.sh`
3. `cd pymt_cfe && uv build`
4. `uvx twine check dist/*`
5. Test install from `dist/pymt_cfe-<version>.tar.gz` in a clean env
6. Verify import/runtime (`from pymt_cfe import CFE`)

---

## Jupyter Notebook / JupyterHub usage

If `pymt_cfe` works in terminal but fails in a notebook with:

- `ImportError: libcfebmi.so... not found`

set `LD_LIBRARY_PATH` in the Jupyter kernel spec (not in a notebook cell with `!export`, which does not persist to the Python kernel process).

1. Create/select a user kernel for your env:

```bash
python -m ipykernel install --user --name pymt-cfe --display-name "Python (pymt-cfe)"
```

2. Edit the kernel file (typically):

```text
~/.local/share/jupyter/kernels/pymt-cfe/kernel.json
```

3. Add top-level `env` key:

```json
{
  "argv": ["/path/to/python", "-m", "ipykernel_launcher", "-f", "{connection_file}"],
  "display_name": "Python (pymt-cfe)",
  "language": "python",
  "metadata": {},
  "env": {
    "LD_LIBRARY_PATH": "/opt/symfluence/data/installs/ngen/extern/cfe/cmake_build"
  }
}
```

4. Restart kernel and re-run notebook.

### Alternative when editing `kernel.json` is difficult

If modifying kernelspec files is not convenient, preload `libcfebmi` in the first notebook cell before importing `pymt_cfe`:

```python
import ctypes
ctypes.CDLL("/opt/symfluence/data/installs/ngen/extern/cfe/cmake_build/libcfebmi.so.1.0.0", mode=ctypes.RTLD_GLOBAL)
```

Then import normally:

```python
from pymt_cfe import CFE
```

> Note: this must be run in each notebook session unless you configure kernel `env` or use a startup hook like `sitecustomize.py`.

## Troubleshooting quick hits

- **`No module named pkg_resources`**
  - Ensure patched `__init__.py` is present (`./post_babelize_patch.sh`).

- **`fatal error: bmi.h: No such file or directory`**
  - CFE headers not discovered. Use patched `setup.py` and/or set `CFE_ROOT`.

- **`ImportError: libcfebmi.so... not found`**
  - Runtime linker cannot find CFE library; set `LD_LIBRARY_PATH` to CFE lib/build dir.

- **`cannot find -lcfebmi` during build**
  - Build linker cannot find CFE library directory; ensure `CFE_LIB_DIR`/`CFE_ROOT` resolve correctly.
