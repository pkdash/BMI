# QUICKSTART: UEB Python BMI Wrapper

Minimal copy-paste workflow to build, install, and test the UBE Python BMI wrapper.

## 1. Build the Docker image

```bash
docker build --pull --no-cache -t ueb-babelizer .
```

## 2. Run container (mount current folder)

Linux/macOS:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  ueb-babelizer
```

Windows (PowerShell):

```powershell
docker run --rm -it `
  -v "${PWD}:/workspace/user" `
  -w /workspace/user `
  ueb-babelizer
```

## 3. Generate, patch, and build

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
- `uv build` in `pymt_ueb/`

Artifacts are written to:

```text
pymt_ueb/dist/
```

## 4. Test inside the container

```bash
cd /workspace/user/pymt_ueb
# ngen currently requires numpy<2 (NOAA-OWP/ngen CMakeLists.txt), so this wrapper is
# built against numpy<2. --no-build-isolation ignores the pin in pyproject.toml, so make
# sure the environment has it first:  python -m pip install "numpy<2"
python -m pip install -e . --no-build-isolation
python -c "from pymt_ueb import UEB; print('pymt_ueb import OK')"
python -c "from pymt_ueb import UEB; m=UEB(); print(m.get_component_name())"
```

## 5. Test initialization

Use a valid UEB `control.dat` and run from a directory where all paths referenced
by that control file resolve correctly:

```bash
python - <<'PY'
from pymt_ueb import UEB

model = UEB()
model.initialize("/absolute/path/to/control.dat")

print("Component:", model.get_component_name())
print("Inputs:", model.get_input_var_names())
print("Outputs:", model.get_output_var_names())
print("Start:", model.get_start_time())
print("Current:", model.get_current_time())
print("End:", model.get_end_time())
print("Step:", model.get_time_step())

model.finalize()
PY
```

## 6. Install the source distribution (tar.gz) in another environment

Copy `pymt_ueb-0.1.0.tar.gz` and `install.sh` into a target folder.

Recommended: use an isolated env first (at the target folder).

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

Or direct install (set UEB paths explicitly if auto-detection fails):

```bash
export UEB_ROOT="$HOME/NextGenVS/ueb_bmi"
export UEB_LIB_DIR="$HOME/NextGenVS/ueb_bmi/cmake_build/src"
export BMICXX_INCLUDE_DIRS="$HOME/NextGenVS/ngen/extern/bmi-cxx"
export LD_LIBRARY_PATH="$UEB_LIB_DIR:$LD_LIBRARY_PATH"

uv pip install /path/to/pymt_ueb-0.1.tar.gz
# fallback
python -m pip install /path/to/pymt_ueb-0.1.tar.gz
```

## Important UEB-specific details

- C++ class: `ueb::BmiUEB`
- Header: `src/bmi/bmi_ueb.hxx`
- Shared library: `libbmiuebcxx.so`
- Typical library directory: `ueb_bmi/cmake_build/src`
- C++ standard: C++17
- Required native dependencies: BMI-CXX headers, Boost serialization, NetCDF
- Current repository defaults `USE_EWTS=ON`; the Docker build sets it `OFF`
- `UEB_SUPPRESS_OUTPUTS=ON` prevents `Finalize()` from writing UEB-native output
  files during wrapper testing
- `control.dat` may contain relative paths, so initialization is sensitive to
  the current working directory

## 5. Install locally against a NextGen checkout

### 5.1 Expected directory structure

```text
~/NextGenVS/
├── ngen/extern/
│   └── bmi-cxx/
│       └── bmi.hxx
└── ueb_bmi/
    ├── CMakeLists.txt
    ├── src/bmi/bmi_ueb.hxx
    └── cmake_build/src/
        └── libbmiuebcxx.so
```

### 5.2 Build the backend

```bash
# UEB is typically cloned outside ngen/extern
cd "$HOME/NextGenVS"
git clone https://github.com/NOAA-OWP/ueb_bmi.git

# Ensure BMI-CXX headers are available
cd "$HOME/NextGenVS/ngen/extern"
git clone https://github.com/csdms/bmi-cxx.git

# Build UEB
cmake \
  -S "$HOME/NextGenVS/ueb_bmi" \
  -B "$HOME/NextGenVS/ueb_bmi/cmake_build" \
  -DBMICXX_INCLUDE_DIRS="$HOME/NextGenVS/ngen/extern/bmi-cxx" \
  -DCMAKE_BUILD_TYPE=Release

cmake --build "$HOME/NextGenVS/ueb_bmi/cmake_build" --target all -j"$(nproc)"
```

### 5.3 Set environment and install

```bash
export UEB_ROOT="$HOME/NextGenVS/ueb_bmi"
export UEB_LIB_DIR="$UEB_ROOT/cmake_build/src"
export BMICXX_INCLUDE_DIRS="$HOME/NextGenVS/ngen/extern/bmi-cxx"
export LD_LIBRARY_PATH="$UEB_LIB_DIR:${LD_LIBRARY_PATH:-}"
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
