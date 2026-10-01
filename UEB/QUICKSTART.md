# QUICKSTART: UEB Python BMI wrapper

## 1. Build the Docker image

```bash
docker build --pull --no-cache -t ueb-babelizer .
```

## 2. Run it with this folder mounted

Linux/macOS:

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  ueb-babelizer
```

Windows PowerShell:

```powershell
docker run --rm -it `
  -v "${PWD}:/workspace/user" `
  -w /workspace/user `
  ueb-babelizer
```

## 3. Generate, patch, and build

Inside the container:

```bash
sed -i 's/\r//' *.sh
chmod +x regen_and_build.sh post_babelize_patch.sh install.sh
./regen_and_build.sh
```

Artifacts are written to:

```text
pymt_ueb/dist/
```

## 4. Test inside the container

```bash
cd /workspace/user/pymt_ueb
python -m pip install -e . --no-build-isolation
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

## 6. Install the source distribution in another environment

Copy `pymt_ueb-0.1.0.tar.gz` and `install.sh` into the same folder, activate the
target Python environment, and run:

```bash
chmod +x install.sh
./install.sh
```

For the local NextGenVS layout, these paths will commonly be:

```bash
export UEB_ROOT="$HOME/NextGenVS/ueb_bmi"
export UEB_LIB_DIR="$HOME/NextGenVS/ueb_bmi/cmake_build/src"
export BMICXX_INCLUDE_DIRS="$HOME/NextGenVS/ngen/extern/bmi-cxx"
export LD_LIBRARY_PATH="$UEB_LIB_DIR:$LD_LIBRARY_PATH"
```

Then:

```bash
./install.sh
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
