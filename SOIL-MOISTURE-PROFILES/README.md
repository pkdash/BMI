# Soil Moisture Profiles Python BMI Wrapper (`pymt_smp`)

Python BMI wrapper for [NOAA-OWP SoilMoistureProfiles](https://github.com/NOAA-OWP/SoilMoistureProfiles), generated using Babelizer.

This repository provides a Docker-based workflow to:

1. Build the Soil Moisture Profiles BMI C++ model
2. Generate a Python BMI wrapper (`pymt_smp`) with Babelizer
3. Patch the generated wrapper so Python can call the C++ BMI methods
4. Build distributable artifacts (`.tar.gz` and wheel) with `uv`
5. Install from the built tarball into a local NextGen Python environment

The backend library is `libsmpbmi.so`.

---

## Important names

| Item | SMP value |
|---|---|
| Python package | `pymt_smp` |
| Python class | `SMP` |
| Shared library | `libsmpbmi.so` |
| CMake project/library | `smpbmi` |
| Header | `bmi_soil_moisture_profile.hxx` |
| C++ BMI class | `BmiSoilMoistureProfile` |
| Source env root | `SMP_ROOT` |
| Library env dir | `SMP_LIB_DIR` |

Do **not** use SFT names such as `pymt_sft`, `libsftbmi.so`, `SFT_ROOT`, or `BmiSoilFreezeThaw`.

---

## Build with Docker

```bash
docker build --pull --no-cache -t smp-babelizer .
```

Windows Command Prompt:

```cmd
docker run --rm -it ^
  -v "%cd%:/workspace/user" ^
  -w /workspace/user ^
  smp-babelizer
```

Inside the container:

```bash
sed -i 's/\r//' regen_and_build.sh post_babelize_patch.sh install.sh
bash ./regen_and_build.sh
```

Artifacts:

```text
pymt_smp/dist/pymt_smp-0.1.tar.gz
pymt_smp/dist/pymt_smp-0.1-*.whl
```

---

## Install into local NextGen pyenv

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

Test:

```bash
python - <<'PY'
from pymt_smp import SMP

smp = SMP()
print(smp.get_component_name())
print("SMP import OK")
PY
```

---

## BMI methods exposed by `SMP`

The wrapper forwards standard BMI calls to `BmiSoilMoistureProfile`:

- `initialize`, `update`, `update_until`, `finalize`
- `get_component_name`, `get_input_item_count`, `get_output_item_count`
- `get_input_var_names`, `get_output_var_names`
- `get_var_grid`, `get_var_type`, `get_var_units`, `get_var_itemsize`, `get_var_nbytes`, `get_var_location`
- `get_current_time`, `get_start_time`, `get_end_time`, `get_time_units`, `get_time_step`
- `get_value`, `get_value_ptr`, `get_value_at_indices`
- `set_value`, `set_value_at_indices`
- `get_grid_rank`, `get_grid_size`, `get_grid_type`, `get_grid_shape`, `get_grid_spacing`, `get_grid_origin`
- `get_grid_x`, `get_grid_y`, `get_grid_z`
- `get_grid_node_count`, `get_grid_edge_count`, `get_grid_face_count`
- `get_grid_edge_nodes`, `get_grid_face_edges`, `get_grid_face_nodes`, `get_grid_nodes_per_face`
- `reset_size`

---

## Troubleshooting

### Old SFT files are being installed

If install output says `pymt_sft`, `SFT_ROOT`, or `libsftbmi.so`, you are using the wrong installer or tarball. The setup folder must contain:

```text
install.sh
pymt_smp-0.1.tar.gz
```

### `cannot find -lsmpbmi`

Set:

```bash
export SMP_LIB_DIR=$HOME/NextGenVS/ngen/extern/SoilMoistureProfiles/cmake_build
export LD_LIBRARY_PATH=$SMP_LIB_DIR:$LD_LIBRARY_PATH
```

### `fatal error: bmi_soil_moisture_profile.hxx: No such file or directory`

Set:

```bash
export SMP_ROOT=$HOME/NextGenVS/ngen/extern/SoilMoistureProfiles/SoilMoistureProfiles
export SMP_INCLUDE_DIR=$SMP_ROOT/include
```
