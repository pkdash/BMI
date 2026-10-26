# QUICKSTART: PET Python BMI Wrapper

Minimal copy-paste workflow to build, install, and test the PET Python BMI wrapper.

## 1. Build the Dokcer image

```bash
docker build --pull --no-cache -t pet-babelizer .
```

## 2. Run container (mount current folder)

Linux/macOS:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  pet-babelizer
```

Windows (PowerShell):

```powershell
docker run --rm -it `
  -v "${PWD}:/workspace/user" `
  -w /workspace/user `
  pet-babelizer
```

## 3. Generate wrapper + patch + build

Inside container:

```bash
cd /workspace/user
sed -i 's/\r//' *.sh
chmod +x *.sh
./regen_and_build.sh
```

This runs:

- `babelize init babel.toml`
- `./post_babelize_patch.sh`
- `uv build` in `pymt_pet/`

Artifacts are written to:

```text
pymt_pet/dist/
```

## 4. Test inside the container

```bash
cd /workspace/user/pymt_pet
# ngen currently requires numpy<2 (NOAA-OWP/ngen CMakeLists.txt), so this wrapper is
# built against numpy<2. --no-build-isolation ignores the pin in pyproject.toml, so make
# sure the environment has it first:  python -m pip install "numpy<2"
python -m pip install -e . --no-build-isolation
python -c "from pymt_pet import PET; print('pymt_pet import OK')"
python -c "from pymt_pet import PET; m=PET(); print(m.get_component_name())"
```

## 5. Install from the source distribution (tar.gz) in another environment (e.g. JupyterHub)

Copy `pymt_pte-*.tar.gz` and `install.sh` into a target folder.

Recommended: use an isolated env first.

```bash
python -m venv .venv-pymt-pet
source .venv-pymt-pet/bin/activate
python -m pip install --upgrade pip
```

(Conda env is also fine.)

```bash
chmod +x install.sh
./install.sh
```

Or direct install (set PET paths explicitly if auto-detection fails):

```bash
export PET_ROOT=/path/to/evapotranspiration
export PET_LIB_DIR=/path/to/evapotranspiration/build   # directory containing libpetbmi.so*
export LD_LIBRARY_PATH="$PET_LIB_DIR:$LD_LIBRARY_PATH"

# use the correct tar.gz file name here
uv pip install /path/to/pymt_pet-0.1.tar.gz
# fallback
python -m pip install /path/to/pymt_pet-0.1.tar.gz
```

If this prints the component name and variable lists, the package and the
`libpetbmi` shared library were found. An `ImportError`/`OSError` mentioning
`libpetbmi.so` means `PET_LIB_DIR` / `LD_LIBRARY_PATH` is not set correctly.

Test the installation (no model config needed):

```bash
python - <<'PY'
from pymt_pet import PET
m = PET()
print(m.get_component_name())
print("inputs :", m.get_input_var_names())
print("outputs:", m.get_output_var_names())
print("pymt_pet import OK")
PY
```

Optional Test: run a short simulation with your own PET BMI config file:

```bash
python - <<'PY'
from pymt_pet import PET
m = PET()
m.initialize("/path/to/pet_config.txt")   # PET BMI config file
print("start/end/step:", m.get_start_time(), m.get_end_time(), m.get_time_step())
m.update()
print("time after one step:", m.get_current_time())
m.finalize()
print("PET run OK")
PY
```

### 5.1. Local NextGen example

```bash
export PET_ROOT="$HOME/NextGenVS/ngen/extern/evapotranspiration"
export PET_LIB_DIR="$PET_ROOT/cmake_build"
export LD_LIBRARY_PATH="$PET_LIB_DIR:${LD_LIBRARY_PATH:-}"
```

Build backend if needed:

```bash
cd "$HOME/NextGenVS/ngen/extern"
git clone https://github.com/NOAA-OWP/evapotranspiration.git
cmake -B evapotranspiration/cmake_build -S evapotranspiration
cmake --build evapotranspiration/cmake_build --target petbmi -j"$(nproc)"
```

## Notes

- Wheels are architecture-specific (`aarch64` vs `x86_64`).
- If import fails with `libpetbmi.so` not found, set `LD_LIBRARY_PATH` to the PET lib/build directory.

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
