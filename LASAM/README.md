# LASAM/CASAM Python BMI Wrapper (`pymt_lasam`)

Adapted from the uploaded CFE Babelizer workflow, but LGAR-C is a C++ BMI rather than a C registration-function BMI.

Native details:

- BMI class: `BmiLGAR`
- Header: `include/bmi_lgar.hxx`
- Shared library: `liblasambmi.so`
- CMake target: `lasambmi`
- C++ standard: C++14
- Package/class: `pymt_lasam.LASAM`

The repository currently describes the catchment model as CASAM, formerly LASAM. The Python package retains `LASAM` to match the native library and existing NextGen terminology.

Typical NextGen layout:

```text
~/NextGenVS/ngen/extern/LGAR-C/
├── include/bmi_lgar.hxx
└── cmake_build/liblasambmi.so
```

Add this to the pyenv activation `LD_LIBRARY_PATH` block:

```bash
$HOME/NextGenVS/ngen/extern/LGAR-C/cmake_build:\
```
