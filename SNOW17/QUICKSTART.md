# QUICKSTART — `pymt_snow17`

## Build Docker image

```bash
docker build --pull --no-cache -t snow17-babelizer .
```

## Run container from Windows CMD

```cmd
docker run --rm -it ^
  -v "%cd%:/workspace/user" ^
  -w /workspace/user ^
  snow17-babelizer
```

## Generate wrapper and tarball inside container

```bash
sed -i 's/\r//' regen_and_build.sh post_babelize_patch.sh install.sh
bash ./regen_and_build.sh
ls -lh pymt_snow17/dist/
```

The source distribution will be:

```text
pymt_snow17/dist/pymt_snow17-0.1.tar.gz
```

## Install in local WSL pyenv ngen environment

Copy `pymt_snow17-0.1.tar.gz` next to `install.sh`, then in WSL:

```bash
pyenv activate Ngen_venv_py3_10_3
export CONDA_PREFIX=$(pyenv prefix)
cd "/mnt/c/Users/Vaishali/Desktop/NextGen/BMI Functions/Python wrappers/pymt_snow17_setup"
export SNOW17_ROOT=$HOME/NextGenVS/ngen/extern/snow17
export SNOW17_LIB_DIR=$HOME/NextGenVS/ngen/extern/snow17/cmake_build
export SNOW17_BMI_DIR=$SNOW17_LIB_DIR
export SNOW17_MOD_DIR=$SNOW17_LIB_DIR/iso_c_bmi
export LD_LIBRARY_PATH=$SNOW17_LIB_DIR:$SNOW17_MOD_DIR:$LD_LIBRARY_PATH
python -m pip install --force-reinstall "numpy==1.26.4"
sed -i 's/\r//' install.sh
bash ./install.sh
```

## Test

```bash
python - <<'PY'
from pymt_snow17 import SNOW17
m = SNOW17()
print(m.get_component_name())
print('SNOW17 import OK')
PY
```

## Build Snow17 locally if needed

```bash
cd $HOME/NextGenVS/ngen/extern/snow17
rm -rf cmake_build
cmake -B cmake_build -S . \
  -DCMAKE_BUILD_TYPE=Release \
  -DISO_C_FORTRAN_BMI_PATH=$HOME/NextGenVS/ngen/extern/iso_c_fortran_bmi
cmake --build cmake_build --target snow17_bmi -j$(nproc)
find cmake_build -name "libsnow17bmi.so*" -print
```
