# NOAH-OWP BMI Python Wrapper (`pymt_noah_owp`)

Python BMI wrapper for the [NOAA-OWP Noah Modular](https://github.com/NOAA-OWP/noah-owp-modular)
land surface model, generated using [Babelizer](https://babelizer.readthedocs.io).

---

## Repository layout

```text
NOAH_OWP/
├── README.md
├── Dockerfile
├── babel.toml
├── regen_and_build.sh
├── post_babelize_patch.sh
├── install.sh
└── pymt_noah_owp/          # generated + patched Python wrapper package
```

---

## Prerequisites

- Docker installed and running
- Run commands from this `NOAH_OWP/` folder

---

## 1) Build the Docker image

```bash
docker build --pull --no-cache -t noah-owp-babelizer .
```

The image:
- Installs Python 3.12, Babelizer, uv, Cython, NumPy via conda-forge
- Installs HDF5, NetCDF-C, and NetCDF-Fortran via conda-forge (consistent versions)
- Clones `noah-owp-modular` at `/workspace/noah-owp-modular`

---

## 2) Run the container

Mount this folder into the container at `/workspace/user`:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  noah-owp-babelizer
```

---

## 3) Build the Noah-OWP model (inside container)

Configure `user_build_options` and build with `-fPIC` (required for shared library):

```bash
cd /workspace/noah-owp-modular
cp config/user_build_options.gfortran.linux user_build_options
sed -i 's#^ COMPILERF90.*# COMPILERF90    =       gfortran#' user_build_options
sed -i 's#^ NETCDFMOD.*# NETCDFMOD      =       -I/opt/conda/include#' user_build_options
sed -i 's#^ NETCDFLIB.*# NETCDFLIB      =       -L/opt/conda/lib -lnetcdf -lnetcdff#' user_build_options
sed -i 's#^ F90FLAGS.*# F90FLAGS       =       -g -fbacktrace -fPIC#' user_build_options
make clean && make testBMI
```

Create the shared library from the compiled object files:

```bash
gfortran -shared -fPIC \
  -o /workspace/noah-owp-modular/libsurfacebmi.so \
  bmi/bmi.o bmi/bmi_noahowp.o src/*.o \
  -L/opt/conda/lib -lnetcdf -lnetcdff
```

---

## 4) Generate and build the Python wrapper

```bash
cd /workspace/user
./regen_and_build.sh
```

This:
1. Regenerates `pymt_noah_owp/` with Babelizer
2. Applies local patches (module name mismatch, `importlib.metadata`, `setup.py`)
3. Builds sdist and wheel with `uv`

Artifacts are created in:
```text
/workspace/user/pymt_noah_owp/dist/
```

---

## 5) Test the wrapper (inside container)

```bash
export LD_LIBRARY_PATH=/workspace/noah-owp-modular:/opt/conda/lib:$LD_LIBRARY_PATH

cd /workspace/user/pymt_noah_owp
pip install -e . --no-build-isolation

python -c "from pymt_noah_owp import NOAH_OWP; print('import OK')"
python -c "
from pymt_noah_owp.lib import NOAH_OWP
m = NOAH_OWP()
print('component name:', m.get_component_name())
"
```

---

## 6) Install from tarball in a target environment (e.g. JupyterHub)

Use `install.sh` to install `pymt_noah_owp` from the built `.tar.gz` into an
active conda environment.

### Step 1 — Find the required paths

Before running `install.sh`, confirm where Noah-OWP is installed on the target system:

```bash
# Find the shared library (libsurfacebmi.so)
find / -name 'libsurfacebmi.so*' 2>/dev/null

# Find the Fortran module files (bmif_2_0.mod, bminoahowp.mod)
find / -name 'bmif_2_0.mod' 2>/dev/null
find / -name 'bminoahowp.mod' 2>/dev/null

# Check if any Noah-related env vars are already set
env | grep -i noah
```

### Step 2 — Activate your conda environment

```bash
conda activate <your-env>
```

### Step 3 — Run the installer

```bash
chmod +x install.sh
./install.sh
```

The script auto-detects `NOAH_LIB_DIR`, `NOAH_ROOT`, and `NOAH_BMI_DIR` by searching
common paths. If auto-detection succeeds you will see:

```
Detected NOAH_LIB_DIR  : /path/to/cmake_build
Detected NOAH_ROOT     : /path/to/noah-owp-modular
Detected NOAH_BMI_DIR  : /path/to/cmake_build/mod
```

### Step 4 — If auto-detection fails

Set the missing variables manually using the paths found in Step 1, then re-run:

```bash
# For cmake builds (most common):
export NOAH_LIB_DIR=/path/to/noah-owp-modular/cmake_build
export NOAH_BMI_DIR=/path/to/noah-owp-modular/cmake_build/mod

# For make builds:
export NOAH_LIB_DIR=/path/to/noah-owp-modular
export NOAH_BMI_DIR=/path/to/noah-owp-modular/bmi

./install.sh
```

### What `install.sh` does
- Locates `libsurfacebmi.so` and Fortran `.mod` files
- Installs the tarball with `uv pip install --no-build-isolation`
- Writes a conda activation hook so `LD_LIBRARY_PATH` is set automatically on future env activations

---

## Key patches applied by `post_babelize_patch.sh`

Babelizer's Fortran template has two mismatches with Noah-OWP that are fixed automatically:

| Generated (wrong) | Patched (correct) |
|---|---|
| `use surfacebmi` | `use bminoahowp` |
| `type (register_bmi)` | `type (bmi_noahowp)` |

Also patches:
- `__init__.py` — uses `importlib.metadata` instead of `pkg_resources`
- `setup.py` — portable Noah path discovery, no `numpy.distutils`
- `MANIFEST.in` — includes `*.f90` and `*.h` in source distribution

---

## Runtime note (`LD_LIBRARY_PATH`)

The wrapper links against `libsurfacebmi.so` at runtime.
`install.sh` writes a conda activation hook to set this automatically.
If needed, set it manually:

```bash
export LD_LIBRARY_PATH=/path/to/libsurfacebmi-dir:$LD_LIBRARY_PATH
```

---

## Jupyter Notebook / JupyterHub usage

If `pymt_noah_owp` works in a terminal but fails in a notebook with
`ImportError: libsurfacebmi.so not found`, configure the Jupyter kernel:

```bash
python -m ipykernel install --user --name pymt-noah-owp --display-name "Python (pymt-noah-owp)"
```

Edit the kernel file (typically `~/.local/share/jupyter/kernels/pymt-noah-owp/kernel.json`)
and add an `env` key:

```json
{
  "argv": ["/path/to/python", "-m", "ipykernel_launcher", "-f", "{connection_file}"],
  "display_name": "Python (pymt-noah-owp)",
  "language": "python",
  "env": {
    "LD_LIBRARY_PATH": "/path/to/noah-owp-modular/cmake_build"
  }
}
```

---

## Troubleshooting

| Error | Fix |
|---|---|
| `Cannot open module file 'bmif_2_0.mod'` | Noah not built yet, or `NOAH_BMI_DIR` not set — see Step 4 above |
| `Cannot open module file 'surfacebmi.mod'` | Patch not applied — run `./post_babelize_patch.sh` |
| `Derived type 'register_bmi' is being used before it is defined` | Patch not applied — run `./post_babelize_patch.sh` |
| `ImportError: libsurfacebmi.so not found` | Set `LD_LIBRARY_PATH` or configure kernel (see above) |
| `No module named 'numpy.distutils'` | Patch not applied — run `./post_babelize_patch.sh` |
| `Could not locate libsurfacebmi.so*` | Set `NOAH_LIB_DIR` manually — see Step 4 above |
| `Could not locate bmif_2_0.mod` | Set `NOAH_BMI_DIR` manually — see Step 4 above |
