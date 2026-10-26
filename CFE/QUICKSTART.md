# QUICKSTART: CFE Python BMI Wrapper

Minimal copy-paste workflow to build, install, and test the CFE Python BMI wrapper.

## 1. Build the Docker image

```bash
docker build --pull --no-cache -t cfe-babelizer .
```

## 2. Run container (mount current folder)

Linux/macOS:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  cfe-babelizer
```

Windows (PowerShell):

```powershell
docker run --rm -it `
  -v "${PWD}:/workspace/user" `
  -w /workspace/user `
  cfe-babelizer
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
- `uv build` in `pymt_cfe/`

Artifacts are written to:

```text
pymt_cfe/dist/
```

## 4. Test inside the container

```bash
cd /workspace/user/pymt_cfe
# ngen currently requires numpy<2 (NOAA-OWP/ngen CMakeLists.txt), so this wrapper is
# built against numpy<2. --no-build-isolation ignores the pin in pyproject.toml, so make
# sure the environment has it first:  python -m pip install "numpy<2"
python -m pip install -e . --no-build-isolation
python -c "from pymt_cfe import CFE; print('pymt_cfe import OK')"
python -c "from pymt_cfe import CFE; m=CFE(); print(m.get_component_name())"
```

## 5. Install from the source distribution (tar.gz) in another environment (e.g. JupyterHub)

Copy `pymt_cfe-*.tar.gz` and `install.sh` into a target folder.

Recommended: use an isolated env first.

```bash
python -m venv .venv-pymt-cfe
source .venv-pymt-cfe/bin/activate
python -m pip install --upgrade pip
```

(Conda env is also fine.)

```bash
chmod +x install.sh
./install.sh
```

Or direct install (set CFE paths explicitly if auto-detection fails):

```bash
export CFE_ROOT=/path/to/cfe
export CFE_LIB_DIR=/path/to/cfe/build   # directory containing libcfebmi.so*
export LD_LIBRARY_PATH="$CFE_LIB_DIR:$LD_LIBRARY_PATH"

# use the correct tar.gz file name here
uv pip install /path/to/pymt_cfe-0.1.tar.gz
# fallback
python -m pip install /path/to/pymt_cfe-0.1.tar.gz
```

Test the installation (no model config needed):

```bash
python - <<'PY'
from pymt_cfe import CFE
m = CFE()
print(m.get_component_name())
print("inputs :", m.get_input_var_names())
print("outputs:", m.get_output_var_names())
print("pymt_cfe import OK")
PY
```

If this prints the component name and variable lists, the package and the
`libcfebmi` shared library were found. An `ImportError`/`OSError` mentioning
`libcfebmi.so` means `CFE_LIB_DIR` / `LD_LIBRARY_PATH` is not set correctly.

Optional: run a short simulation with your own CFE BMI config file:

```bash
python - <<'PY'
from pymt_cfe import CFE
m = CFE()
m.initialize("/path/to/cfe_config.txt")   # CFE BMI config file
print("start/end/step:", m.get_start_time(), m.get_end_time(), m.get_time_step())
m.update()
print("time after one step:", m.get_current_time())
m.finalize()
print("CFE run OK")
PY
```

### 5.1. Local NextGen example

```bash
export CFE_ROOT="$HOME/NextGenVS/ngen/extern/cfe"
export CFE_LIB_DIR="$CFE_ROOT/cmake_build"
export LD_LIBRARY_PATH="$CFE_LIB_DIR:${LD_LIBRARY_PATH:-}"
```

Build backend if needed:

```bash
cd "$HOME/NextGenVS/ngen/extern"
git clone https://github.com/NOAA-OWP/cfe.git
cmake -B cfe/cmake_build -S cfe
cmake --build cfe/cmake_build --target cfebmi -j"$(nproc)"
```

## Notes

- Wheels are architecture-specific (`aarch64` vs `x86_64`).
- If import fails with `libcfebmi.so` not found, set `LD_LIBRARY_PATH` to the CFE lib/build directory.

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
