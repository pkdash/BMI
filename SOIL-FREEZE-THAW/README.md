# Soil-Freeze-Thaw Python BMI Wrapper (`pymt_sft`)

Python BMI wrapper for the [NOAA-OWP SoilFreezeThaw](https://github.com/NOAA-OWP/SoilFreezeThaw), generated using [Babelizer](https://babelizer.readthedocs.io).

This repository provides a Docker-based workflow to:

1. Build the Soil-Freeze-Thaw (SFT) BMI C++ model
2. Generate a Python BMI wrapper (`pymt_sft`) with Babelizer
3. Test the wrapper in-container
4. Build distributable artifacts (`.tar.gz`, wheel) with `uv`
5. Install from the built tarball

The Soil-Freeze-Thaw model itself is a 1-D soil hydrology and freeze–thaw physics model (Zhu et al., 2018) that simulates soil temperature, moisture, ice content, and drainage over an arbitrary number of soil layers.

---

## Repository layout

```text
SOIL-FREEZE-THAW/
├── README.md
├── QUICKSTART.md|
├── Dockerfile
├── babel.toml
├── regen_and_build.sh
├── post_babelize_patch.sh
├── install.sh
└── pymt_sft/          # generated + patched Python wrapper package
```

---

## Prerequisites

- Docker installed and running
- This repository checked out locally
- Run commands from this `SOIL-FREEZE-THAW` folder

## Environment recommendation

For local testing/installation outside Docker, install `pymt_sft` in an isolated environment (recommended):

- Conda env, or
- Python virtual environment (`venv`)

This prevents dependency conflicts with your base environment and makes troubleshooting much easier.

Example with `venv`:

```bash
python -m venv .venv-pymt-sft
source .venv-pymt-sft/bin/activate
python -m pip install --upgrade pip
```

Example with conda:

```bash
conda create -n pymt-sft python=3.11 -y
conda activate pymt-sft
```

---

## 1) Build the Docker image

Use image name **`sft-babelizer`**:

```bash
docker build --pull --no-cache -t sft-babelizer .
```

> `--no-cache` is recommended when troubleshooting dependency/build changes.

The image:

- Base: `mambaorg/micromamba:2.3.2`
- System packages (via `apt`): `build-essential`, `g++`, `cmake`, `git`, `pkg-config`
- Python environment (via `micromamba`):
  - `python=3.12`
  - `babelizer=0.3.9`
  - `uv`
  - `pip`
  - `setuptools=69.5.1`
  - `numpy`
  - `cython`
  - `wheel`
  - `compilers`
- SFT model: cloned from `https://github.com/NOAA-OWP/SoilFreezeThaw.git` into `/workspace/sft`
  - Built with `cmake -DNGEN=ON && cmake --build` (produces `libsftbmi.so`)
  - `LD_LIBRARY_PATH=/workspace/sft/build`

> **Note:** The PyMT SFT wrapper (`pymt_sft`) is **not** installed in the image. It is generated and mounted at runtime from your host directory.

---

## 2) Run the container (mount current folder)

Mount the current host folder into the container at `/workspace/user`:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  sft-babelizer
```

Notes:
- SFT is already cloned and built inside the image at `/workspace/sft`.
- `LD_LIBRARY_PATH` is set in the image to `/workspace/sft/build`.

---

## 3) Generate the SFT BMI Python module with Babelizer

Inside the container:

```bash
# from /workspace/user
babelize init babel.toml
```

This generates/updates the `pymt_sft/` package scaffold.

### Reapply local custom patches after regeneration

Babelizer can overwrite custom files. Use:

```bash
./post_babelize_patch.sh
```

This reapplies:
- `pymt_sft/pymt_sft/__init__.py` (`importlib.metadata` version handling)
- `pymt_sft/setup.py` (portable SFT path discovery, C++ flags)
- `pymt_sft/pymt_sft/lib/sft.pyx` (full BMI method implementation — the babelizer only generates the C++ extern skeleton, not the Python-visible methods)

### One-shot regenerate + patch + build

Optional cleanup before regeneration (recommended while iterating):

```bash
# from /workspace/user
python -m pip uninstall -y pymt_sft || true
rm -rf pymt_sft/build pymt_sft/dist pymt_sft/*.egg-info
find pymt_sft -type d -name "__pycache__" -prune -exec rm -rf {} +
find pymt_sft -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete
```

Then run:

```bash
./regen_and_build.sh
```

---

## 4) Test `pymt_sft` in the container

Install editable (from generated package folder):

```bash
cd /workspace/user/pymt_sft
python -m pip install -e . --no-build-isolation
```

Quick import test:

```bash
python -c "from pymt_sft import SFT; print('pymt_sft import OK')"
python -c "from pymt_sft import SFT; m=SFT(); print(m.get_component_name())"
```

If needed, verify the extension and linked libraries:

```bash
python -c "import pymt_sft.lib.sft as m; print(m.__file__)"
ldd $(python -c "import pymt_sft.lib.sft as m; print(m.__file__)")
```

---

## 5) Build distributable package files (`tar.gz` and wheel)

Inside `pymt_sft/`:

```bash
cd /workspace/user/pymt_sft
rm -rf build dist *.egg-info
uv build
```

Artifacts are created in:

```text
/workspace/user/pymt_sft/dist/
```

Optional checks:

```bash
uvx twine check dist/*
```

---

## 6) Install using built `.tar.gz`

### In a target environment (example)

Direct install may work if SFT paths are auto-detected. If not, set SFT paths explicitly first.

```bash
# Recommended explicit setup for direct install
# Find the path containing the SoilFreezeThaw bmi.h header file
find / -name 'bmi/bmi.h' 2>/dev/null
export SFT_ROOT=/path/to/SoilFreezeThaw # directory containing SoilFreezeThaw bmi/bmi.h

find / -name "libsftbmi.so*" 2>/dev/null
export SFT_LIB_DIR=/path/to/SoilFreezeThaw/cmake_build   # directory containing libsftbmi.so*
export LD_LIBRARY_PATH="$SFT_LIB_DIR:$LD_LIBRARY_PATH"

uv pip install /path/to/pymt_sft-0.1.tar.gz
```

If `uv` is not available:

```bash
python -m pip install /path/to/pymt_sft-0.1.tar.gz
```

### Helper installer script (recommended)

This repo includes `install.sh` (same directory as tarball) that:
- Detects active conda env
- Finds SFT paths programmatically
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
- Wheel built on `aarch64` will not install on `x86_64`

For cross-platform testing, prefer installing the source distribution (`.tar.gz`) on the target machine, or build wheels on matching architecture.

---

## Suggested release checklist

1. `babelize init babel.toml`
2. `./post_babelize_patch.sh`
3. `cd pymt_sft && uv build`
4. `uvx twine check dist/*`
5. Test install from `dist/pymt_sft-<version>.tar.gz` in a clean env
6. Verify import/runtime (`from pymt_sft import SFT; m=SFT(); print(m.get_component_name())`)

---

## Jupyter Notebook / JupyterHub usage

If `pymt_sft` works in terminal but fails in a notebook with:

- `ImportError: libsftbmi.so... not found`

set `LD_LIBRARY_PATH` in the Jupyter kernel spec (not in a notebook cell with `!export`, which does not persist to the Python kernel process).

1. Create/select a user kernel for your env:

```bash
python -m ipykernel install --user --name pymt-sft --display-name "Python (pymt-sft)"
```

2. Edit the kernel file (typically):

```text
~/.local/share/jupyter/kernels/pymt-sft/kernel.json
```

3. Add top-level `env` key (replace `<SFT_BUILD_DIR>` with the actual SFT build directory on your host):

```json
{
  "argv": ["/path/to/python", "-m", "ipykernel_launcher", "-f", "{connection_file}"],
  "display_name": "Python (pymt-sft)",
  "language": "python",
  "metadata": {},
  "env": {
    "LD_LIBRARY_PATH": "<SFT_BUILD_DIR>"
  }
}
```

4. Restart kernel and re-run notebook.

### Alternative when editing `kernel.json` is difficult

If modifying kernelspec files is not convenient, preload `libsftbmi` in the first notebook cell before importing `pymt_sft` (replace `<SFT_BUILD_DIR>` with the actual path):

```python
import ctypes
ctypes.CDLL("<SFT_BUILD_DIR>/libsftbmi.so", mode=ctypes.RTLD_GLOBAL)
```

Then import normally:

```python
from pymt_sft import SFT
```

> Note: this must be run in each notebook session unless you configure kernel `env` or use a startup hook like `sitecustomize.py`.

---

## BMI Methods Exposed by `SFT`

All standard [CSDMS BMI functions](https://bmi.readthedocs.io/en/stable/bmi.data.html) are implemented in the Cython wrapper, delegating to the C++ `BmiSoilFreezeThaw` class:

| Category | Methods |
|----------|---------|
| **Control** | `initialize`, `update`, `update_until`, `finalize` |
| **Model info** | `get_component_name`, `get_input/output_item_count`, `get_input/output_var_names` |
| **Variable info** | `get_var_grid/type/units/itemsize/nbytes/location` |
| **Time** | `get_current_time`, `get_start_time`, `get_end_time`, `get_time_units`, `get_time_step` |
| **Value I/O** | `get_value`, `get_value_ptr`, `get_value_at_indices`, `set_value`, `set_value_at_indices` |
| **Grid** | `get_grid_rank/size/type/shape/spacing/origin/x/y/z/node_count/edge_count/face_count/edge_nodes/face_edges/face_nodes/nodes_per_face` |

### Architecture

```text
┌─────────────────────┐
│  PyMT / user Python │
│  from pymt_sft      │
│      import SFT     │
└──────────┬──────────┘
           │  Cython cdef class
           │  (sft.pyx)
           ▼
┌─────────────────────┐
│  BmiSoilFreezeThaw  │  ← C++ class
│  (bmi_soil_freeze_  │     from SFT source
│   thaw.hxx)         │
└─────────────────────┘
```

The `sft.pyx` file:
1. Declares the `BmiSoilFreezeThaw` C++ class via `cdef extern`.
2. Wraps it in a Python `cdef class SFT`.
3. Implements every BMI method by forwarding calls to the internal `self._bmi` instance (e.g., `self._bmi.GetComponentName()`).

**Important:** The babelizer only generates the C++ extern declaration; the Python-visible `SFT` cdef class methods must be implemented separately.  Without these, trying to call e.g. `m.get_component_name()` raises `AttributeError` because the C++ methods are not automatically exposed.

String and vector types are handled automatically by Cython directives:
```
# cython: c_string_type=str, c_string_encoding=ascii
```
This means `std::string` and `std::vector<std::string>` returned by the C++ BMI methods are transparently converted to Python `str` and `tuple` without manual encoding.

---

## Notes / Limitations

- `get_value(self, name, dest)` **requires** the caller to pre-allocate the `dest` NumPy array and pass it in. It returns the same array for convenience but only copies data into the existing storage.
- `get_value_ptr(self, name)` returns a NumPy array view into the model's internal memory (zero copy). Do not hold this past `finalize()`.
- The model is a **1-D vertical model**; grids are typically `uniform_rectilinear` with a single dimension equal to the number of soil/ice layers.
- The Cython extension links against `libsftbmi` (C++ standard: `-std=c++14` is passed to the compiler).

---

## Files of Interest

| File | What It Holds |
|------|---------------|
| `pymt_sft/lib/sft.pyx` | Cython → C++ BMI wrapper (full implementation, including all BMI `def` methods) |
| `pymt_sft/bmi.py` | Python shim: re-exports `SFT` for PyMT |
| `pymt_sft/__init__.py` | Package init, `__version__` via `importlib.metadata`, re-exports `SFT` |
| `pymt_sft/lib/__init__.py` | Module init: `from .sft import SFT` |
| `meta/SFT/api.yaml` | PyMT plugin manifest (name, language, class) |
| `setup.py` / `pyproject.toml` | Build configuration, Extension definition |

---

## Troubleshooting quick hits

- **`No module named pkg_resources`**
  - Ensure patched `__init__.py` is present (`./post_babelize_patch.sh`).

- **`fatal error: bmi_soil_freeze_thaw.hxx: No such file or directory`**
  - SFT headers not discovered. Use patched `setup.py` and/or set `SFT_ROOT`.

- **`ImportError: libsftbmi.so... not found`**
  - Runtime linker cannot find SFT library; set `LD_LIBRARY_PATH` to SFT lib/build dir.

- **`cannot find -lsftbmi` during build`**
  - Build linker cannot find SFT library directory; ensure `SFT_LIB_DIR` / `SFT_ROOT` resolve correctly.

- **`AttributeError: 'pymt_sft.lib.sft.SFT' object has no attribute 'get_component_name'`**
  - The Cython `sft.pyx` was babelized but not patched. Run `./post_babelize_patch.sh` to inject the full BMI method implementations into `pymt_sft/lib/sft.pyx`.

---

## License

MIT. See the original `LICENSE` file for details.

## Reference

Zhu, L., et al. (2018). **Soil Freeze-Thaw** ... *(adapted for CSDMS BMI).*
