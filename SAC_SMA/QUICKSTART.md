# QUICKSTART: Sac-SMA Python BMI Wrapper

Minimal copy-paste workflow to build, install, and test the Sac-SMA Python BMI wrapper.

## 1. Build the Docker image

```bash
docker build --pull --no-cache -t sac-sma-babelizer .
```

## 2. Run the container (mount current folder)

Linux/macOS:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  sac-sma-babelizer
```

Windows (PowerShell):

```powershell
docker run --rm -it `
  -v "${PWD}:/workspace/user" `
  -w /workspace/user `
  sac-sma-babelizer
```

## 3. Confirm the native model is present

```bash
find /workspace/sac-sma -name "bmi_sac.f90" -print
find /workspace/sac-sma -name "libsacbmi.so*" -print
find /workspace/sac-sma/cmake_build -iname "*.mod" -print | head
```

## 4. Generate wrapper + patch + build

```bash
cd /workspace/user
sed -i 's/\r//' *.sh
chmod +x *.sh
./regen_and_build.sh
```

This runs:

- `babelize init babel.toml`
- `./post_babelize_patch.sh`
- `uv build` in `pymt_sac_sma/`

Artifacts are written to:

```text
pymt_sac_sma/dist/
```

## 5. Test inside the container

```bash
export LD_LIBRARY_PATH=/workspace/sac-sma/cmake_build:${LD_LIBRARY_PATH:-}

cd /workspace/user/pymt_sac_sma
# ngen currently requires numpy<2 (NOAA-OWP/ngen CMakeLists.txt), so this wrapper is
# built against numpy<2. --no-build-isolation ignores the pin in pyproject.toml, so make
# sure the environment has it first:  python -m pip install "numpy<2"
python -m pip install -e . --no-build-isolation
python -c "from pymt_sac_sma import SAC_SMA; print('pymt_sac_sma import OK')"
python -c "from pymt_sac_sma import SAC_SMA; m=SAC_SMA(); print(m.get_component_name())"
```

## 6. Install from the source distribution (tar.gz) in another environment (e.g. JupyterHub)

Copy `pymt_sac_sma-*.tar.gz` and `install.sh` into a target folder.

Recommended: use an isolated env first.

```bash
python -m venv .venv-pymt-sac_sma
source .venv-pymt-sac_sma/bin/activate
python -m pip install --upgrade pip
```

(Conda env is also fine.)

```bash
chmod +x install.sh
./install.sh
```

Or direct install (set SAC_SMA paths explicitly if auto-detection fails):

```bash
export SAC_SMA_ROOT=/path/to/sac-sma
export SAC_SMA_LIB_DIR=/path/to/sac-sma/cmake_build   # directory containing libsacbmi.so*
export LD_LIBRARY_PATH="$SAC_SMA_LIB_DIR:$LD_LIBRARY_PATH"

# use the correct tar.gz file name here
uv pip install /path/to/pymt_sac_sma-0.1.0.tar.gz
# fallback
python -m pip install /path/to/pymt_sac_sma-0.1.0.tar.gz
```

Test the installation (no model config needed):

```bash
python - <<'PY'
from pymt_sac_sma import SAC_SMA
m = SAC_SMA()
print(m.get_component_name())
print("inputs :", m.get_input_var_names())
print("outputs:", m.get_output_var_names())
print("pymt_sac_sma import OK")
PY
```

Optional Test: run a short simulation with your own SAC_SMA BMI config file:

```bash
python - <<'PY'
from pymt_sac_sma import SAC_SMA
m = SAC_SMA()
m.initialize("/path/to/sac_sma_config.txt")   # SAC_SMA BMI config file
print("start/end/step:", m.get_start_time(), m.get_end_time(), m.get_time_step())
m.update()
print("time after one step:", m.get_current_time())
m.finalize()
print("SAC_SMA run OK")
PY
```

## 7. Install for a local NextGen setup

### 7.1 Expected directory structure

```text
~/NextGenVS/ngen/extern/
├── iso_c_fortran_bmi/
└── sac-sma/
    ├── CMakeLists.txt
    ├── src/bmi/bmi_sac.f90
    └── cmake_build/
        └── libsacbmi.so
```

### 7.2 Build the backend

```bash
cd "$HOME/NextGenVS/ngen/extern"
git clone https://github.com/NOAA-OWP/sac-sma.git

cmake \
  -S sac-sma \
  -B sac-sma/cmake_build \
  -DISO_C_FORTRAN_BMI_PATH="$HOME/NextGenVS/ngen/extern/iso_c_fortran_bmi" \
  -DCMAKE_BUILD_TYPE=Release

cmake --build sac-sma/cmake_build \
  --target sacbmi \
  -j"$(nproc)"
```

### 7.3 Set environment and install

```bash
export SAC_SMA_ROOT="$HOME/NextGenVS/ngen/extern/sac-sma"
export SAC_SMA_LIB_DIR="$SAC_SMA_ROOT/cmake_build"
export ISO_C_FORTRAN_BMI_PATH="$HOME/NextGenVS/ngen/extern/iso_c_fortran_bmi"
export LD_LIBRARY_PATH="$SAC_SMA_LIB_DIR:${LD_LIBRARY_PATH:-}"
```

Then run `install.sh` beside the generated tarball.

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
