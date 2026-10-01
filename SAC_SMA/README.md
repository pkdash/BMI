# Sac-SMA Python BMI Wrapper (`pymt_sac_sma`)

This workflow generates a Python/PyMT wrapper for the BMI-enabled NOAA-OWP
Sacramento Soil Moisture Accounting model.

## Native implementation

- Repository: `NOAA-OWP/sac-sma`
- Primary language: Fortran
- BMI module: `bmi_sac_module`
- BMI derived type: `bmi_sac`
- CMake shared-library target: `sacbmi`
- Runtime library: `libsacbmi.so`
- NextGen dependency: `extern/iso_c_fortran_bmi`

## Why post-generation patching is required

Babelizer derives the Fortran module and derived-type names from the library and
entry-point fields. The actual Sac-SMA identifiers do not match those generated
names. `post_babelize_patch.sh` changes the generated interoperability source to:

```fortran
use bmi_sac_module
type (bmi_sac)
```

This is analogous to the Noah-OWP patch pattern, but uses Sac-SMA's real module
and type.

## BMI variables in the current Sac-SMA implementation

Inputs:

- `tair` — `degC`
- `precip` — `mm/s`
- `pet` — `mm/s`

The current implementation exposes 11 outputs, including `qs`, `qg`, `tci`,
`eta`, and runoff/baseflow components.

## Build notes

The shared library cannot be built as an NGen-compatible Fortran BMI module
unless CMake can access `iso_c_fortran_bmi`. Configure with:

```bash
-DISO_C_FORTRAN_BMI_PATH=/path/to/ngen/extern/iso_c_fortran_bmi
```

Then build:

```bash
cmake --build cmake_build --target sacbmi
```
