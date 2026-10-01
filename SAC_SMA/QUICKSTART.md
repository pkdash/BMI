# QUICKSTART — `pymt_sac_sma`

## 1. Build the Docker image

```bash
docker build --pull --no-cache -t sac-sma-babelizer .
```

## 2. Run the container

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  sac-sma-babelizer
```

PowerShell:

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

## 4. Generate, patch, and build

```bash
sed -i 's/\r//' *.sh
chmod +x regen_and_build.sh post_babelize_patch.sh install.sh
./regen_and_build.sh
```

Artifacts:

```text
pymt_sac_sma/dist/
```

## 5. Test in the container

```bash
export LD_LIBRARY_PATH=/workspace/sac-sma/cmake_build:${LD_LIBRARY_PATH:-}

cd /workspace/user/pymt_sac_sma
python -m pip install -e . --no-build-isolation

cd ~
python - <<'PY'
from pymt_sac_sma import SAC_SMA

model = SAC_SMA()
print(model.get_component_name())
print("pymt_sac_sma import OK")
PY
```

## 6. Install locally against a NextGen checkout

Expected layout:

```text
~/NextGenVS/ngen/extern/
├── iso_c_fortran_bmi/
└── sac-sma/
    ├── src/bmi/bmi_sac.f90
    └── cmake_build/libsacbmi.so
```

Build the backend:

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

Set paths:

```bash
export SAC_SMA_ROOT="$HOME/NextGenVS/ngen/extern/sac-sma"
export SAC_SMA_LIB_DIR="$SAC_SMA_ROOT/cmake_build"
export ISO_C_FORTRAN_BMI_PATH="$HOME/NextGenVS/ngen/extern/iso_c_fortran_bmi"
export LD_LIBRARY_PATH="$SAC_SMA_LIB_DIR:${LD_LIBRARY_PATH:-}"
```

Then run `install.sh` beside the generated tarball.
