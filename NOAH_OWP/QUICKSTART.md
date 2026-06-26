# QUICKSTART — `pymt_noah_owp`

Minimal copy-paste workflow to build, install, and test the NOAH-OWP Python BMI wrapper.

---

## 1) Build the Docker image

```bash
docker build --pull --no-cache -t noah-owp-babelizer .
```

---

## 2) Run the container (mount current folder)

```bash
# Linux/MacOS
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  noah-owp-babelizer
```

```powershell
# Windows (PowerShell)
docker run --rm -it `
  -v "${PWD}:/workspace/user" `
  -w /workspace/user `
  noah-owp-babelizer
```

```cmd
:: Windows (Command Prompt)
docker run --rm -it ^
  -v "%cd%:/workspace/user" ^
  -w /workspace/user ^
  noah-owp-babelizer
```

---

## 3) Build Noah-OWP model + shared library (inside container)

```bash
cd /workspace/noah-owp-modular
cp config/user_build_options.gfortran.linux user_build_options
sed -i 's#^ COMPILERF90.*# COMPILERF90    =       gfortran#' user_build_options
sed -i 's#^ NETCDFMOD.*# NETCDFMOD      =       -I/opt/conda/include#' user_build_options
sed -i 's#^ NETCDFLIB.*# NETCDFLIB      =       -L/opt/conda/lib -lnetcdf -lnetcdff#' user_build_options
sed -i 's#^ F90FLAGS.*# F90FLAGS       =       -g -fbacktrace -fPIC#' user_build_options
make clean && make testBMI

gfortran -shared -fPIC \
  -o /workspace/noah-owp-modular/libsurfacebmi.so \
  bmi/bmi.o bmi/bmi_noahowp.o src/*.o \
  -L/opt/conda/lib -lnetcdf -lnetcdff
```

---

## 4) Generate wrapper + patch + build (inside container)

```bash
cd /workspace/user
./regen_and_build.sh
```

This runs:
- `babelize init babel.toml`
- `./post_babelize_patch.sh` (fixes Fortran module name mismatches + setup.py)
- `uv build` in `pymt_noah_owp/`

Artifacts end up in:

```text
pymt_noah_owp/dist/
```

---

## 5) Test in container

```bash
export LD_LIBRARY_PATH=/workspace/noah-owp-modular:/opt/conda/lib:$LD_LIBRARY_PATH

cd /workspace/user/pymt_noah_owp
pip install -e . --no-build-isolation

python -c "from pymt_noah_owp import NOAH_OWP; print('pymt_noah_owp import OK')"
python -c "
from pymt_noah_owp.lib import NOAH_OWP
m = NOAH_OWP()
print('component name:', m.get_component_name())
"
```

---

## 6) Install from tar.gz (target env e.g. JupyterHub)

Activate your conda environment first:

```bash
conda activate <your-env>
```

Place `pymt_noah_owp-*.tar.gz` and `install.sh` in the same folder, then:

```bash
chmod +x install.sh
./install.sh
```

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

./install.sh
```

---

## Notes

- Wheels are architecture-specific (`aarch64` vs `x86_64`) — use the `.tar.gz` for cross-platform installs.
- If import fails with `libsurfacebmi.so not found`, set `LD_LIBRARY_PATH` to the directory containing `libsurfacebmi.so`.
- In JupyterHub notebooks, configure the kernel `env` in `kernel.json` to persist `LD_LIBRARY_PATH` across sessions (see `README.md`).

## Windows: CRLF line-ending fix

The shell scripts (`*.sh`) must have Unix LF line endings or bash inside the
Linux container will fail with errors like:

```
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
