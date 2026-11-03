# UEB Python BMI Wrapper (`pymt_ueb`)

This folder adapts the existing SFT Babelizer workflow to the NGWPC UEB BMI
implementation.

## Architecture

```text
Python / PyMT
    |
    | Cython extension: pymt_ueb.lib.ueb
    v
ueb::BmiUEB
    |
    v
libbmiuebcxx.so
```

The upstream UEB BMI implementation is C++ and exposes the standard BMI methods
through the `ueb::BmiUEB` class declared in `src/bmi/bmi_ueb.hxx`.

## Repository contents

- `Dockerfile`: builds UEB and its native dependencies
- `babel.toml`: Babelizer configuration
- `regen_and_build.sh`: clean generation, patching, and package build
- `post_babelize_patch.sh`: inserts the complete Cython BMI implementation
- `install.sh`: installs the source distribution against an existing UEB build
- `QUICKSTART.md`: copy-paste workflow

## Why the SFT files cannot merely be renamed

UEB differs from SFT in several important ways:

1. Its class is namespaced: `ueb::BmiUEB`.
2. Its library is `libbmiuebcxx.so`.
3. Its public BMI header is under `src/bmi`.
4. It compiles as C++17.
5. It links against NetCDF and Boost serialization.
6. It requires the external BMI-CXX header `bmi.hxx`.
7. The current development branch enables EWTS logging by default, so a
   standalone wrapper build should set `-DUSE_EWTS=OFF` unless EWTS is installed.
8. The model also provides Gregorian-calendar helper methods, which this wrapper
   exposes as:
   - `get_start_time_gregorian()`
   - `get_current_time_gregorian()`
   - `get_end_time_gregorian()`

## Build

See `QUICKSTART.md`.

## Expected local UEB layout

A typical local build is:

```text
~/NextGenVS/
├── ueb_bmi/
│   ├── src/bmi/bmi_ueb.hxx
│   └── cmake_build/src/libbmiuebcxx.so
└── ngen/extern/bmi-cxx/bmi.hxx
```

Set:

```bash
export UEB_ROOT="$HOME/NextGenVS/ueb_bmi"
export UEB_LIB_DIR="$UEB_ROOT/cmake_build/src"
export BMICXX_INCLUDE_DIRS="$HOME/NextGenVS/ngen/extern/bmi-cxx"
export LD_LIBRARY_PATH="$UEB_LIB_DIR:$LD_LIBRARY_PATH"
```

## Limitation

These files are structurally adapted and checked against the current upstream
header/build layout, but the complete Docker build was not executed in this
offline sandbox. The first actual build may expose a Babelizer-version-specific
scaffold detail or a platform-specific linker dependency. The patch script is
designed to replace the generated Cython and setup files, which minimizes that
risk.
