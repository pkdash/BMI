# QUICKSTART

Minimal copy-paste workflow for building and installing the SFT Python BMI wrapper.

## 1) Build image

```bash
docker build --pull --no-cache -t sft-babelizer .
```

## 2) Run container (mount current folder)

```bash
docker run --rm -it \
  -v "$(pwd)":/workspace/user \
  -w /workspace/user \
  sft-babelizer
```

## 3) Generate wrapper + patch + build

Inside the container:

```bash
chmod +x regen_and_build.sh post_babelize_patch.sh
./regen_and_build.sh
```

This runs:

1. `babelize init babel.toml` — generates `pymt_sft/`
2. `./post_babelize_patch.sh` — writes the C++ shim, patches the generated pyx, replaces `setup.py` and `__init__.py`
3. `uv build` in `pymt_sft/`

Artifacts end up in:

```text
pymt_sft/dist/
```

## 4) Test in container

```bash
cd /workspace/user/pymt_sft
python -m pip install -e . --no-build-isolation
python -c "from pymt_sft import SFT; print('pymt_sft import OK')"
```

## 5) Install from tar.gz (target env)

```bash
chmod +x install.sh
./install.sh
```

Or direct install (set SFT paths explicitly if auto-detection fails):

```bash
export SFT_ROOT=/path/to/SoilFreezeThaw
export SFT_LIB_DIR=/path/to/SoilFreezeThaw/build   # dir containing libsftbmi.so
export LD_LIBRARY_PATH="$SFT_LIB_DIR:$LD_LIBRARY_PATH"

pip install /path/to/pymt_sft-0.1.tar.gz
```

## Notes

- **`register_bmi_sft` shim**: the upstream SFT library does not expose a
  C-compatible `register_bmi_sft`.  `post_babelize_patch.sh` writes
  `pymt_sft/pymt_sft/lib/sft_bmi_shim.{h,cxx}` which bridges the C++
  `BmiSoilFreezeThaw` class to the C-style `Bmi` struct that babelizer expects,
  and updates `setup.py` to compile it alongside the Cython extension.

- **Build flag**: `libsftbmi.so` is produced by `-DNGEN=ON`.  No git submodules
  are needed for this target (SoilMoistureProfiles is only used by PFRAMEWORK).

- **`-DBMI_ACTIVE`**: the SFT CMakeLists sets this via `add_compile_definitions`;
  `setup.py` mirrors it so the shim and pyx see the same preprocessor state.

- If the import fails with `libsftbmi.so not found`, set `LD_LIBRARY_PATH` to
  the SFT build directory.
