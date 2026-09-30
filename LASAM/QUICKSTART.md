# QUICKSTART: LASAM/CASAM Python BMI wrapper

```bash
docker build --pull --no-cache -t lasam-babelizer .
docker run --rm -it -v "$(pwd)":/workspace/user -w /workspace/user lasam-babelizer
```

Inside the container:

```bash
sed -i 's/\r//' *.sh
chmod +x *.sh
./regen_and_build.sh
```

Artifacts are in `pymt_lasam/dist/`.

Test:

```bash
cd /workspace/user/pymt_lasam
python -m pip install -e . --no-build-isolation
cd ~
python -c "from pymt_lasam import LASAM; print(LASAM().get_component_name())"
```

Local NextGen paths:

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
