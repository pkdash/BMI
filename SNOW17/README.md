# Snow17 Python BMI Wrapper (`pymt_snow17`)

Python BMI/PyMT wrapper scaffold for NOAA-OWP Snow17.

Snow17 builds a NextGen BMI shared library named `libsnow17bmi.so` using the CMake target `snow17_bmi`.

## Files

- `Dockerfile`
- `babel.toml`
- `regen_and_build.sh`
- `post_babelize_patch.sh`
- `install.sh`
- `QUICKSTART.md`

## Important patch

Babelizer derives names from the shared library, but Snow17 uses the Fortran module and derived type:

```fortran
module bmi_snow17_module
type, extends(bmi) :: bmi_snow17
```

`post_babelize_patch.sh` updates the generated `bmi_interoperability.f90` to use `bmi_snow17_module` and `type(bmi_snow17)`.

## Docker build

```bash
docker build --pull --no-cache -t snow17-babelizer .
```

## Generate package

```bash
docker run --rm -it -v "$(pwd)":/workspace/user -w /workspace/user snow17-babelizer
sed -i 's/\r//' regen_and_build.sh post_babelize_patch.sh install.sh
bash ./regen_and_build.sh
```

## Local install

```bash
export SNOW17_ROOT=$HOME/NextGenVS/ngen/extern/snow17
export SNOW17_LIB_DIR=$HOME/NextGenVS/ngen/extern/snow17/cmake_build
export SNOW17_BMI_DIR=$SNOW17_LIB_DIR
export SNOW17_MOD_DIR=$SNOW17_LIB_DIR/iso_c_bmi
export LD_LIBRARY_PATH=$SNOW17_LIB_DIR:$SNOW17_MOD_DIR:$LD_LIBRARY_PATH
bash ./install.sh
```
