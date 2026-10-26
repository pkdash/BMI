# QUICKSTART — Snow17 Python BMI Wrapper

Minimal copy-paste workflow for building and installing the SFT Python BMI wrapper.

## 1. Build the Docker image

```bash
docker build --pull --no-cache -t snow17-babelizer .
```

## 2. Run container (mount current folder)

Linux/macOS:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  snow17-babelizer
```

Windows (PowerShell):

```powershell
docker run --rm -it `
  -v "${PWD}:/workspace/user" `
  -w /workspace/user `
  snow17-babelizer
```

## 3. Generate wrapper + patch + build

Inside the container:

```bash
cd /workspace/user
sed -i 's/\r//' *.sh
chmod +x *.sh
./regen_and_build.sh
```

This runs:

- `babelize init babel.toml`
- `./post_babelize_patch.sh`
- `uv build` in `pymt_snow17/`

Artifacts are written to:

```text
pymt_snow17/dist/
```

## 4. Test inside the container

```bash
export LD_LIBRARY_PATH=$SNOW17_LIB_DIR:$SNOW17_MOD_DIR:$LD_LIBRARY_PATH

cd /workspace/user/pymt_snow17
# ngen currently requires numpy<2 (NOAA-OWP/ngen CMakeLists.txt), so this wrapper is
# built against numpy<2. --no-build-isolation ignores the pin in pyproject.toml, so make
# sure the environment has it first:  python -m pip install "numpy<2"
pip install -e . --no-build-isolation

python -c "from pymt_snow17 import SNOW17; print('pymt_snow17 import OK')"
python -c "from pymt_snow17 import SNOW17; m=SNOW17(); print(m.get_component_name())"
```

## 5. Install from the source distribution (tar.gz) in another environment (e.g. JupyterHub)

Copy `pymt_snow17-*.tar.gz` and `install.sh` into a target folder.

Recommended: use an isolated env first.

```bash
python -m venv .venv-pymt-snow17
source .venv-pymt-snow17/bin/activate
python -m pip install --upgrade pip
```

(Conda/pyenv env is also fine.)

```bash
export CONDA_PREFIX=$(pyenv prefix)   # or your venv/conda prefix
chmod +x install.sh
./install.sh
```

Or direct install (set SNOW17 paths explicitly if auto-detection fails):

```bash
export SNOW17_ROOT=/path/to/snow17
export SNOW17_LIB_DIR=/path/to/snow17/cmake_build   # directory containing libsnow17bmi.so*
export SNOW17_BMI_DIR=$SNOW17_LIB_DIR
export SNOW17_MOD_DIR=$SNOW17_LIB_DIR/iso_c_bmi
export LD_LIBRARY_PATH="$SNOW17_LIB_DIR:$SNOW17_MOD_DIR:$LD_LIBRARY_PATH"

# use the correct tar.gz file name here
uv pip install /path/to/pymt_snow17-0.1.tar.gz
# fallback
python -m pip install --no-build-isolation /path/to/pymt_snow17-0.1.tar.gz
```

If this prints the component name and variable lists, the package and the
`libsnow17bmi` shared library were found. An `ImportError`/`OSError` mentioning
`libsnow17bmi.so` means `SNOW17_LIB_DIR` / `LD_LIBRARY_PATH` is not set correctly.

Test the installation (no model config needed):

```bash
python - <<'PY'
from pymt_snow17 import SNOW17
m = SNOW17()
print(m.get_component_name())
print("inputs :", m.get_input_var_names())
print("outputs:", m.get_output_var_names())
print("pymt_snow17 import OK")
PY
```

Optional Test: Run a short simulation with your own SNOW17 BMI config file:

```bash
python - <<'PY'
from pymt_snow17 import SNOW17
m = SNOW17()
m.initialize("/path/to/snow17_config.txt")   # SNOW17 BMI config file
print("start/end/step:", m.get_start_time(), m.get_end_time(), m.get_time_step())
m.update()
print("time after one step:", m.get_current_time())
m.finalize()
print("SNOW17 run OK")
PY
```

### 5.1. Local NextGen example

#### 5.1.1 Expected directory structure

```text
~/NextGenVS/ngen/extern/
├── iso_c_fortran_bmi/
└── snow17/
    ├── CMakeLists.txt
    └── cmake_build/
        └── libsnow17bmi.so
```

#### 5.1.2 Set environment and build

```bash
# activate your pyenv/venv/conda environment first (optional)
export CONDA_PREFIX=$(pyenv prefix)   # or your venv/conda prefix
export SNOW17_ROOT="$HOME/NextGenVS/ngen/extern/snow17"
export SNOW17_LIB_DIR="$SNOW17_ROOT/cmake_build"
export SNOW17_BMI_DIR="$SNOW17_LIB_DIR"
export SNOW17_MOD_DIR="$SNOW17_LIB_DIR/iso_c_bmi"
export LD_LIBRARY_PATH="$SNOW17_LIB_DIR:$SNOW17_MOD_DIR:${LD_LIBRARY_PATH:-}"
```

Build backend if needed: see [Build Snow17 locally if needed](#build-snow17-locally-if-needed) below.

Copy `pymt_snow17-*.tar.gz` and `install.sh` into a folder, then:

```bash
cd /path/to/folder
python -m pip install --force-reinstall "numpy==1.26.4"
sed -i 's/\r//' install.sh
./install.sh
```

Test:

```bash
python - <<'PY'
from pymt_snow17 import SNOW17
m = SNOW17()
print(m.get_component_name())
print('SNOW17 import OK')
PY
```

Build Snow17 locally if needed:

```bash
cd $HOME/NextGenVS/ngen/extern/snow17
rm -rf cmake_build
cmake -B cmake_build -S . \
  -DCMAKE_BUILD_TYPE=Release \
  -DISO_C_FORTRAN_BMI_PATH=$HOME/NextGenVS/ngen/extern/iso_c_fortran_bmi
cmake --build cmake_build --target snow17_bmi -j$(nproc)
find cmake_build -name "libsnow17bmi.so*" -print
```

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
