# QUICKSTART

Minimal copy-paste workflow for building and installing the **SMP / Soil Moisture Profiles** Python BMI wrapper.

## 1) Build image

```bash
docker build --pull --no-cache -t smp-babelizer .
```

## 2) Run container

```cmd
:: Windows Command Prompt
docker run --rm -it ^
  -v "%cd%:/workspace/user" ^
  -w /workspace/user ^
  smp-babelizer
```

```bash
# Linux/MacOS
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  smp-babelizer
```

## 3) Generate wrapper + patch + build

Inside the container:

```bash
sed -i 's/\r//' regen_and_build.sh post_babelize_patch.sh install.sh
bash ./regen_and_build.sh
```

This creates:

```text
pymt_smp/dist/pymt_smp-0.1.tar.gz
pymt_smp/dist/pymt_smp-0.1-*.whl
```

## 4) Test in container

```bash
cd /workspace/user/pymt_smp
python -m pip install -e . --no-build-isolation
python -c "from pymt_smp import SMP; print('pymt_smp import OK')"
python -c "from pymt_smp import SMP; m=SMP(); print(m.get_component_name())"
```

## 5) Install from tar.gz in local NextGen pyenv

```bash
pyenv activate Ngen_venv_py3_10_3
export CONDA_PREFIX=$(pyenv prefix)

cd "/mnt/c/Users/Vaishali/Desktop/NextGen/BMI Functions/Python wrappers/pymt_smp_setup"

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

## 6) Test local install

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
