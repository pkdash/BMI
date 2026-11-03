# QUICKSTART: LASAM/CASAM Python BMI Wrapper

Minimal copy-paste workflow.

## 1. Build the Docker image

```bash
docker build --pull --no-cache -t lasam-babelizer .
```

## 2. Run container (mount current folder)

Linux/macOS:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  lasam-babelizer
```

Windows (PowerShell):

```powershell
docker run --rm -it `
  -v "${PWD}:/workspace/user" `
  -w /workspace/user `
  lasam-babelizer
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
- `uv build` in `pymt_lasam/`

Artifacts are written to:

```text
pymt_lasam/dist/
```

## 4. Test inside the container

```bash
cd /workspace/user/pymt_lasam
# ngen currently requires numpy<2 (NOAA-OWP/ngen CMakeLists.txt), so this wrapper is
# built against numpy<2. --no-build-isolation ignores the pin in pyproject.toml, so make
# sure the environment has it first:  python -m pip install "numpy<2"
python -m pip install -e . --no-build-isolation
python -c "from pymt_lasam import LASAM; print('pymt_lasam import OK')"
python -c "from pymt_lasam import LASAM; m=LASAM(); print(m.get_component_name())"
```

## 5. Install from the source distribution (tar.gz) in another environment

Copy `pymt_lasam-0.1.0.tar.gz` and `install.sh` into a target folder

Recommended: use an isolated env first (at the target folder).

```bash
python -m venv .venv-pymt-lasam
source .venv-pymt-lasam/bin/activate
python -m pip install --upgrade pip
```

(Conda env is also fine.)

```bash
chmod +x install.sh
./install.sh
```

Or direct install (set LASAM paths explicitly if auto-detection fails):

```bash
export LASAM_ROOT=/path/to/lgar-c
export LASAM_LIB_DIR=/path/to/lgar-c/cmake_build   # directory containing liblasambmi.so*
export LD_LIBRARY_PATH="$LASAM_LIB_DIR:${LD_LIBRARY_PATH:-}"

uv pip install /path/to/pymt_lasam-0.1.0.tar.gz
# fallback
python -m pip install /path/to/pymt_lasam-0.1.0.tar.gz
```

If this prints the component name and variable lists, the package and the
`liblasambmi` shared library were found. An `ImportError`/`OSError` mentioning
`liblasambmi.so` means `LASAM_LIB_DIR` / `LD_LIBRARY_PATH` is not set correctly.

Test the installation (no model config needed):

```bash
python - <<'PY'
from pymt_lasam import LASAM
m = LASAM()
print(m.get_component_name())
print("inputs :", m.get_input_var_names())
print("outputs:", m.get_output_var_names())
print("pymt_lasam import OK")
PY
```

Optional Test: Run a short simulation with your own LASAM BMI config file:

```bash
python - <<'PY'
from pymt_lasam import LASAM
m = LASAM()
m.initialize("/path/to/lasam_config.txt")   # LASAM BMI config file
print("start/end/step:", m.get_start_time(), m.get_end_time(), m.get_time_step())
m.update()
print("time after one step:", m.get_current_time())
m.finalize()
print("LASAM run OK")
PY
```

### 5.1. Install for a local NextGen setup

#### 5.1.1 Expected directory structure

```text
~/NextGenVS/ngen/extern/
└── LGAR-C/
    ├── CMakeLists.txt
    └── cmake_build/
        └── liblasambmi.so
```

#### 5.1.2 Set environment and build

```bash
export LASAM_ROOT="$HOME/NextGenVS/ngen/extern/LGAR-C"
export LASAM_LIB_DIR="$LASAM_ROOT/cmake_build"
export LD_LIBRARY_PATH="$LASAM_LIB_DIR:${LD_LIBRARY_PATH:-}"
```

Build backend if needed:

```bash
cd "$HOME/NextGenVS/ngen/extern"
git clone https://github.com/NOAA-OWP/LGAR-C.git
cmake -B LGAR-C/cmake_build -S LGAR-C
cmake --build LGAR-C/cmake_build --target lasambmi -j"$(nproc)"
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
