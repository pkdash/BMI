# QUICKSTART - SMP (Soil Moisture Profiles) Python BMI Wrapper

Minimal copy-paste workflow for building and installing the **SMP / Soil Moisture Profiles** Python BMI wrapper.

## 1. Build the Docker image

```bash
docker build --pull --no-cache -t smp-babelizer .
```

## 2. Run the container (mount current folder)

Linux/macOS:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  smp-babelizer
```

Windows (PowerShell):

```powershell
docker run --rm -it `
  -v "${PWD}:/workspace/user" `
  -w /workspace/user `
  smp-babelizer
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
- `uv build` in `pymt_smt/`

Artifacts are written to:

```text
pymt_smp/dist/
```

## 4. Test inside the container

```bash
cd /workspace/user/pymt_smp
# ngen currently requires numpy<2 (NOAA-OWP/ngen CMakeLists.txt), so this wrapper is
# built against numpy<2. --no-build-isolation ignores the pin in pyproject.toml, so make
# sure the environment has it first:  python -m pip install "numpy<2"
python -m pip install -e . --no-build-isolation
python -c "from pymt_smp import SMP; print('pymt_smp import OK')"
python -c "from pymt_smp import SMP; m=SMP(); print(m.get_component_name())"
```

## 5. Install from the source distribution (tar.gz) in another environment (e.g. JupyterHub)

Copy `pymt_smp-*.tar.gz` and `install.sh` into a target folder.

Recommended: use an isolated env first.

```bash
python -m venv .venv-pymt-smp
source .venv-pymt-smp/bin/activate
python -m pip install --upgrade pip
```

(Conda env is also fine. `install.sh` installs into the env pointed to by `CONDA_PREFIX`; for a venv or pyenv, run `export CONDA_PREFIX=$VIRTUAL_ENV` or `export CONDA_PREFIX=$(pyenv prefix)` first.)

```bash
sed -i 's/\r//' install.sh
chmod +x install.sh
./install.sh
```

Or direct install (set SMP paths explicitly if auto-detection fails):

```bash
export SMP_ROOT=/path/to/SoilMoistureProfiles
export SMP_LIB_DIR=/path/to/SoilMoistureProfiles/cmake_build   # directory containing libsmpbmi.so*
export SMP_INCLUDE_DIR="$SMP_ROOT/include"
export LD_LIBRARY_PATH="$SMP_LIB_DIR:$LD_LIBRARY_PATH"

# use the correct tar.gz file name here
uv pip install /path/to/pymt_smp-0.1.tar.gz
# fallback
python -m pip install --no-build-isolation /path/to/pymt_smp-0.1.tar.gz
```

Test the installation (no model config needed):

```bash
python - <<'PY'
from pymt_smp import SMP
m = SMP()
print(m.get_component_name())
print("inputs :", m.get_input_var_names())
print("outputs:", m.get_output_var_names())
print("pymt_smp import OK")
PY
```

## 6. Install from tar.gz in local NextGen pyenv

```bash
pyenv activate Ngen_venv_py3_10_3
export CONDA_PREFIX=$(pyenv prefix)

# Directory containing install.sh and pymt_smp-0.1.tar.gz
# (on WSL, Windows drives are under /mnt/c/..., e.g. /mnt/c/Users/<you>/...)
cd /path/to/pymt_smp_setup

export SMP_ROOT=$HOME/NextGenVS/ngen/extern/SoilMoistureProfiles/SoilMoistureProfiles
export SMP_LIB_DIR=$HOME/NextGenVS/ngen/extern/SoilMoistureProfiles/cmake_build
export SMP_INCLUDE_DIR=$SMP_ROOT/include
export LD_LIBRARY_PATH=$SMP_LIB_DIR:$LD_LIBRARY_PATH

python -m pip install --force-reinstall "numpy==1.26.4"

sed -i 's/\r//' install.sh
bash ./install.sh
```

Direct fallback:

```bash
python -m pip install --force-reinstall --no-build-isolation --no-deps ./pymt_smp-0.1.tar.gz
```

Test local install:

```bash
python - <<'PY'
from pymt_smp import SMP

smp = SMP()
print(smp.get_component_name())
print("SMP import OK")
PY
```

## Important

Use SMP names only:

```text
pymt_smp
SMP
libsmpbmi.so
SMP_ROOT
SMP_LIB_DIR
bmi_soil_moisture_profile.hxx
BmiSoilMoistureProfile
```

Do not use old SFT names such as `pymt_sft`, `SFT`, `libsftbmi.so`, or `SFT_ROOT`.

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
