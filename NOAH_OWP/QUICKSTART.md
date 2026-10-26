# QUICKSTART — NOAH-OWP Python BMI Wrapper

Minimal copy-paste workflow to build, install, and test the NOAH-OWP Python BMI wrapper.

---

> **Note:** `Dockerfile` pins the upstream `noah-owp-modular` checkout to a
> commit before it switched its build system from Make to CMake (2026-07-15).
> This keeps `make clean && make testBMI` below working. See `README.md` for
> details and a TODO to migrate this repo to the new CMake build.

## 1. Build the Docker image

```bash
docker build --pull --no-cache -t noah-owp-babelizer .
```

---

## 2. Run the container (mount current folder)

Linux/macOS:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  noah-owp-babelizer
```

Windows (PowerShell):

```powershell
docker run --rm -it `
  -v "${PWD}:/workspace/user" `
  -w /workspace/user `
  noah-owp-babelizer
```

---

## 3. Build Noah-OWP model + shared library (inside container)

```bash
cd /workspace/noah-owp-modular

# Create user_build_options with gfortran + conda-forge NetCDF settings
cat > user_build_options << 'EOF'
 COMPILERF90    =       gfortran
 NETCDFMOD      =       -I/opt/conda/include
 NETCDFLIB      =       -L/opt/conda/lib -lnetcdf -lnetcdff
 F90FLAGS       =       -g -fbacktrace -fPIC
EOF

make clean && make testBMI

gfortran -shared -fPIC \
  -o /workspace/noah-owp-modular/libsurfacebmi.so \
  bmi/bmi.o bmi/bmi_noahowp.o src/*.o \
  -L/opt/conda/lib -lnetcdf -lnetcdff
```

---

## 4. Generate wrapper + patch + build

Inside the container:

```bash
cd /workspace/user
sed -i 's/\r//' *.sh
chmod +x *.sh
./regen_and_build.sh
```

This runs:

- `babelize init babel.toml`
- `./post_babelize_patch.sh` (fixes Fortran module name mismatches + setup.py)
- `uv build` in `pymt_noah_owp/`

Artifacts are written to:

```text
pymt_noah_owp/dist/
```

---

## 5. Test inside the container

```bash
export LD_LIBRARY_PATH=/workspace/noah-owp-modular:/opt/conda/lib:$LD_LIBRARY_PATH

cd /workspace/user/pymt_noah_owp
# ngen currently requires numpy<2 (NOAA-OWP/ngen CMakeLists.txt), so this wrapper is
# built against numpy<2. --no-build-isolation ignores the pin in pyproject.toml, so make
# sure the environment has it first:  python -m pip install "numpy<2"
pip install -e . --no-build-isolation

python -c "from pymt_noah_owp import NOAH_OWP; print('pymt_noah_owp import OK')"
python -c "
from pymt_noah_owp.lib import NOAH_OWP
m = NOAH_OWP()
print('component name:', m.get_component_name())
"
```

---

## 6. Install from the source distribution (tar.gz) in another environment (e.g. JupyterHub)

Copy `pymt_noah_owp-*.tar.gz` and `install.sh` into a target folder.

Recommended: use an isolated env first.

```bash
python -m venv .venv-pymt-noah-owp
source .venv-pymt-noah-owp/bin/activate
python -m pip install --upgrade pip
```

(Conda env is also fine.)

The script auto-detects `libsurfacebmi.so` and Fortran `.mod` file locations.
If auto-detection fails, find the paths first:

```bash
find / -name 'libsurfacebmi.so*' 2>/dev/null
find / -name 'bmif_2_0.mod' 2>/dev/null
```

Then set manually and re-run:

```bash
# cmake build layout (most common):
export NOAH_LIB_DIR=/path/to/noah-owp-modular/cmake_build
export NOAH_BMI_DIR=/path/to/noah-owp-modular/cmake_build/mod

# make build layout:
export NOAH_LIB_DIR=/path/to/noah-owp-modular
export NOAH_BMI_DIR=/path/to/noah-owp-modular/bmi

chmod +x install.sh
./install.sh
```

Or direct install (set NOAH-OWP paths explicitly if auto-detection fails):

```bash
export NOAH_ROOT=/path/to/noah-owp-modular
export NOAH_LIB_DIR=/path/to/noah-owp-modular/cmake_build   # directory containing libsurfacebmi.so*
export NOAH_BMI_DIR=/path/to/noah-owp-modular/cmake_build/mod   # directory containing bmif_2_0.mod
export LD_LIBRARY_PATH="$NOAH_LIB_DIR:${LD_LIBRARY_PATH:-}"

# use the correct tar.gz file name here
uv pip install /path/to/pymt_noah_owp-0.1.tar.gz
# fallback
python -m pip install /path/to/pymt_noah_owp-0.1.tar.gz
```

If this prints the component name and variable lists, the package and the
`libsurfacebmi` shared library were found. An `ImportError`/`OSError` mentioning
`libsurfacebmi.so` means `NOAH_LIB_DIR` / `LD_LIBRARY_PATH` is not set correctly.

Test the installation (no model config needed):

```bash
python - <<'PY'
from pymt_noah_owp import NOAH_OWP
m = NOAH_OWP()
print(m.get_component_name())
print("inputs :", m.get_input_var_names())
print("outputs:", m.get_output_var_names())
print("pymt_noah_owp import OK")
PY
```

Optional Test: run a short simulation with your own NOAH-OWP BMI config file:

```bash
python - <<'PY'
from pymt_noah_owp import NOAH_OWP
m = NOAH_OWP()
m.initialize("/path/to/noah_owp_config.namelist")   # NOAH-OWP BMI config file
print("start/end/step:", m.get_start_time(), m.get_end_time(), m.get_time_step())
m.update()
print("time after one step:", m.get_current_time())
m.finalize()
print("NOAH_OWP run OK")
PY
```

---

## Notes

- Wheels are architecture-specific (`aarch64` vs `x86_64`) — use the `.tar.gz` for cross-platform installs.
- If import fails with `libsurfacebmi.so not found`, set `LD_LIBRARY_PATH` to the directory containing `libsurfacebmi.so`.
- In JupyterHub notebooks, configure the kernel `env` in `kernel.json` to persist `LD_LIBRARY_PATH` across sessions (see `README.md`).

## Windows: CRLF line-ending fix

The shell scripts (`*.sh`) must have Unix LF line endings or bash inside the
Linux container will fail with errors like:

```text
$'\r': command not found
```

**Prevention (recommended):** The repo ships a `.gitattributes` file that
forces LF for `*.sh`, `*.toml`, and `Dockerfile`. As long as you clone with a
Git client that respects `.gitattributes` (Git ≥ 2.10), no extra steps are
needed.

**One-time fix if you already have CRLF files:**

Option A — using Git:

```powershell
git config core.autocrlf false
git rm --cached -r .
git reset --hard
```

Option B — using `dos2unix` (install via [Chocolatey](https://chocolatey.org/) or WSL):

```powershell
dos2unix regen_and_build.sh post_babelize_patch.sh install.sh
```

Option C — inside the running container (quickest workaround):

```bash
sed -i 's/\r//' /workspace/user/regen_and_build.sh
sed -i 's/\r//' /workspace/user/post_babelize_patch.sh
```
