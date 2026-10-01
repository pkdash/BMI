# TOPMODEL BMI Python Wrapper (`pymt_topmodel`)

Python BMI wrapper for the [NOAA-OWP TOPMODEL](https://github.com/NOAA-OWP/topmodel), generated using [Babelizer](https://babelizer.readthedocs.io).

This repository provides a Docker-based workflow to:

1. Build NOAA-OWP TOPMODEL BMI C model
2. Generate a Python BMI wrapper (`pymt_topmodel`) with Babelizer
3. Test the wrapper in-container
4. Build distributable artifacts (`.tar.gz`, wheel) with `uv`
5. Install from the built tarball

---

## Repository layout

```text
TOPMODEL/
├── README.md
├── QUICKSTART.md
├── Dockerfile
├── babel.toml
├── regen_and_build.sh
├── post_babelize_patch.sh
├── install.sh
└── pymt_topmodel/          # generated + patched Python wrapper package
```

---

## Prerequisites

- Docker installed and running
- This repository checked out locally
- Run commands from this `TOPMODEL` folder

## Environment recommendation

For local testing/installation outside Docker, install `pymt_topmodel` in an isolated environment (recommended):

- Conda env, or
- Python virtual environment (`venv`)

This prevents dependency conflicts with your base environment and makes troubleshooting much easier.

Example with `venv`:

```bash
python -m venv .venv-pymt-topmodel
source .venv-pymt-topmodel/bin/activate
python -m pip install --upgrade pip
```

Example with conda:

```bash
conda create -n pymt-topmodel python=3.11 -y
conda activate pymt-topmodel
```

---

## 1) Build the Docker image

Use image name **`topmodel-babelizer`**:

```bash
docker build --pull --no-cache -t topmodel-babelizer .
```

> `--no-cache` is recommended when troubleshooting dependency/build changes.

---

## 2) Run the container (mount current folder)

Mount the current host folder into the container at `/workspace/user`:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  topmodel-babelizer
```

Notes:
- TOPMODEL is already cloned and built inside the image at `/workspace/topmodel`.
- `LD_LIBRARY_PATH` is set in the image to `/workspace/topmodel/build`.

---

## 3) Generate the TOPMODEL BMI Python module with Babelizer

Inside the container:

```bash
# from /workspace/user
babelize init babel.toml
```

This generates/updates the `pymt_topmodel/` package scaffold.

### Reapply local custom patches after regeneration

Babelizer can overwrite custom files. Use:

```bash
./post_babelize_patch.sh
```

This reapplies:
- `pymt_topmodel/pymt_topmodel/__init__.py` (`importlib.metadata` version handling)
- `pymt_topmodel/setup.py` (portable TOPMODEL path discovery)

### One-shot regenerate + patch + build

Optional cleanup before regeneration (recommended while iterating):

```bash
# from /workspace/user
python -m pip uninstall -y pymt_topmodel || true
rm -rf pymt_topmodel/build pymt_topmodel/dist pymt_topmodel/*.egg-info
find pymt_topmodel -type d -name "__pycache__" -prune -exec rm -rf {} +
find pymt_topmodel -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete
```

Then run:

```bash
./regen_and_build.sh
```

---

## 4) Test `pymt_topmodel` in the container

Install editable (from generated package folder):

```bash
cd /workspace/user/pymt_topmodel
python -m pip install -e . --no-build-isolation
```

Quick import test:

```bash
python -c "from pymt_topmodel import TOPMODEL; print('pymt_topmodel import OK')"
python -c "from pymt_topmodel.lib import TOPMODEL; m=TOPMODEL(); print(m.get_component_name())"
```

If needed, verify the extension and linked libraries:

```bash
python -c "import pymt_topmodel.lib.topmodel as m; print(m.__file__)"
ldd $(python -c "import pymt_topmodel.lib.topmodel as m; print(m.__file__)")
```

---

## 5) Build distributable package files (`tar.gz` and wheel)

Inside `pymt_topmodel/`:

```bash
cd /workspace/user/pymt_topmodel
rm -rf build dist *.egg-info
uv build
```

Artifacts are created in:

```text
/workspace/user/pymt_topmodel/dist/
```

Optional checks:

```bash
uvx twine check dist/*
```

---

## 6) Install using built `.tar.gz`

### In a target environment

Direct install may work if TOPMODEL paths are auto-detected. If not, set TOPMODEL paths explicitly first.

```bash
# Find the TOPMODEL BMI header
find / -name 'bmi_topmodel.h' 2>/dev/null
export TOPMODEL_ROOT=/path/to/topmodel        # directory containing include/bmi_topmodel.h

# Find the path containing libtopmodelbmi.so*
find / -name "libtopmodelbmi.so*" 2>/dev/null
export TOPMODEL_LIB_DIR=/path/to/topmodel/build   # directory containing libtopmodelbmi.so*

export LD_LIBRARY_PATH="$TOPMODEL_LIB_DIR:$LD_LIBRARY_PATH"

uv pip install /path/to/pymt_topmodel-0.1.tar.gz
```

If `uv` is not available:

```bash
python -m pip install /path/to/pymt_topmodel-0.1.tar.gz
```

### Helper installer script (recommended)

This repo includes `install.sh` (same directory as tarball) that:
- Detects active conda/pyenv-style env through `CONDA_PREFIX`
- Finds TOPMODEL paths programmatically
- Sets required env vars for installation
- Installs tarball with the active env's `python -m pip`
- Avoids mixed conda compiler/linker setups
- Writes conda activation hook to set `LD_LIBRARY_PATH`

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
3. `cd pymt_topmodel && uv build`
4. `uvx twine check dist/*`
5. Test install from `dist/pymt_topmodel-<version>.tar.gz` in a clean env
6. Verify import/runtime (`from pymt_topmodel import TOPMODEL`)

---

## Jupyter Notebook / JupyterHub usage

If `pymt_topmodel` works in terminal but fails in a notebook with:

- `ImportError: libtopmodelbmi.so... not found`

set `LD_LIBRARY_PATH` in the Jupyter kernel spec.

1. Create/select a user kernel for your env:

```bash
python -m ipykernel install --user --name pymt-topmodel --display-name "Python (pymt-topmodel)"
```

2. Edit the kernel file, typically:

```text
~/.local/share/jupyter/kernels/pymt-topmodel/kernel.json
```

3. Add top-level `env` key:

```json
{
  "argv": ["/path/to/python", "-m", "ipykernel_launcher", "-f", "{connection_file}"],
  "display_name": "Python (pymt-topmodel)",
  "language": "python",
  "metadata": {},
  "env": {
    "LD_LIBRARY_PATH": "/path/to/directory/containing/libtopmodelbmi.so"
  }
}
```

4. Restart kernel and re-run notebook.

### Alternative when editing `kernel.json` is difficult

If modifying kernelspec files is not convenient, preload `libtopmodelbmi` in the first notebook cell before importing `pymt_topmodel`:

```python
import ctypes
ctypes.CDLL("/path/to/libtopmodelbmi.so.1.0.0", mode=ctypes.RTLD_GLOBAL)
```

Then import normally:

```python
from pymt_topmodel import TOPMODEL
```

## Troubleshooting quick hits

- **`No module named pkg_resources`**
  - Ensure patched `__init__.py` is present (`./post_babelize_patch.sh`).

- **`fatal error: bmi.h: No such file or directory`**
  - TOPMODEL headers were not discovered. Use patched `setup.py` and/or set `TOPMODEL_ROOT`.

- **`ImportError: libtopmodelbmi.so... not found`**
  - Runtime linker cannot find TOPMODEL library; set `LD_LIBRARY_PATH` to TOPMODEL lib/build dir.

- **`cannot find -ltopmodelbmi` during build**
  - Build linker cannot find TOPMODEL library directory; ensure `TOPMODEL_LIB_DIR`/`TOPMODEL_ROOT` resolve correctly.
