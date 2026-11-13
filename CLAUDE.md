# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A monorepo of Python BMI wrappers (`pymt_<model>` packages, generated with CSDMS Babelizer) for ten hydrological models. Each top-level model directory (`CFE`, `PET`, `TOPMODEL` in C; `SOIL-FREEZE-THAW`/`pymt_sft`, `SOIL-MOISTURE-PROFILES`/`pymt_smp`, `LASAM`, `UEB` in C++; `NOAH_OWP`, `SAC_SMA`, `SNOW17` in Fortran) is self-contained and has the same file set: `babel.toml`, `Dockerfile`, `regen_and_build.sh`, `post_babelize_patch.sh`, `install.sh`, `wrapper/`, `pymt_<model>/`, `README.md` and `QUICKSTART.md`.

## Where edits must go (generated vs. source)

The committed `pymt_<model>/` tree is Babelizer output. `regen_and_build.sh` deletes it and regenerates it, so **a hand edit inside `pymt_<model>/` is lost on the next regeneration** unless it is also made in one of these places:

- **`common/`**: shared Cython layer for all value exchange (`get_value`, `get_value_ptr`, `set_value`, `*_at_indices`, lifecycle guards). `templates/{c,cxx,fortran}.pyx.in` hold one template per language family, `bmi_arrays.py` holds the dtype/size/casting rules, and `bmi_ptr.pxi` holds the pointer-to-NumPy-view logic. Per-model options that `babel.toml` can't express (C++ namespace, string encoding, extra methods) live in the `MODELS` dict in `common/render_wrappers.py`.
- **`<MODEL>/post_babelize_patch.sh`**: per-model fixes applied after `babelize init`. It runs `wrapper/install.sh` to copy the rendered `.pyx` and helpers into the package, rewrites `__init__.py` (importlib.metadata) and `setup.py` (library/header discovery via env vars, pkg-config and well-known paths, plus an embedded `-Wl,-rpath`), pins `numpy<2` in `pyproject.toml`, and keeps the generated `.c` files in the sdist.
- **`<MODEL>/babel.toml`**: library name, header, entry point and the in-container include/library dirs (`/workspace/<model>/...`).

After changing anything in `common/`, re-render, then commit both the `<MODEL>/wrapper/` output and the `pymt_<model>/pymt_<model>/lib/` output:

```sh
python common/render_wrappers.py            # all models (or pass model dir names)
python common/render_wrappers.py --check    # fails if any rendered output is stale
```

The renderer needs Python 3.11+ (or `pip install tomli`). `<MODEL>/wrapper/` is vendored per model because the Docker workflow mounts only the model directory.

To add a new model: create the directory with the standard files, register it in `MODELS` in `render_wrappers.py`, then render.

## Build (per model, inside its Docker image)

From `<MODEL>/QUICKSTART.md`:

```sh
docker build --pull --no-cache -t <model>-babelizer .
docker run --rm -it -v "$(pwd)":/workspace/user -w /workspace/user <model>-babelizer
# inside the container:
./regen_and_build.sh          # babelize init -> post_babelize_patch.sh -> uv build (artifacts in pymt_<model>/dist/)
cd pymt_<model>
python -m pip install "numpy<2"
python -m pip install -e . --no-build-isolation
python -c "from pymt_cfe import CFE; print(CFE().get_component_name())"
```

Some models need an extra native build step before `regen_and_build.sh` (for example, NOAH_OWP's step 3 runs `make testBMI` and links `libsurfacebmi.so`). Check that model's QUICKSTART.

`numpy<2` is deliberate: the main consumer, NOAA-OWP/ngen, rejects numpy>=2. Because `--no-build-isolation` bypasses the `pyproject.toml` pin, the environment must already have numpy<2.

`<MODEL>/install.sh` installs a built sdist (or the source tree) into another environment such as JupyterHub. It locates the native `lib<model>bmi.so` and headers (using env vars such as `CFE_LIB_DIR`/`CFE_ROOT`) and picks a compatible compiler.

## Tests

```sh
# Unit tests for common/bmi_arrays.py (no native libraries needed)
python -m pytest common/tests/test_bmi_arrays.py
python -m pytest common/tests/test_bmi_arrays.py::<test_name>

# Native contract suite. Run where the wrappers are installed; each model runs only if its config is set.
# Keys: CFE PET TOPMODEL SFT SMP LASAM UEB NOAH_OWP SAC_SMA SNOW17
export PYMT_CFE_CONFIG=/path/to/cfe_config.txt
export PYMT_CFE_WORKDIR=/path/to/dir     # optional chdir before initialize
python -X faulthandler -m pytest common/tests/test_native_models.py -v
```

To test end to end after changing anything that affects the wrappers (`common/`, templates, patch scripts, `setup.py`, Dockerfiles, `babel.toml`), use the project skill `/test-bmi-wrappers`. It runs every QUICKSTART flow in Docker on scratch copies, then runs the contract suite. You can also call its script directly:

```sh
.claude/skills/test-bmi-wrappers/scripts/run_quickstart_tests.sh --out <dir> [--no-contract] [--no-cache] [MODEL ...]
```

## `bmi_setup/` (Python package over the wrappers)

`bmi_setup/` is the BMI-generic setup layer, numpy only. It is not generated, so edit it directly.

- **What it contains:** `open_model`/`Model` (safe lifecycle, scalar broadcast), per-model parameter catalogs in `bmi_setup/catalogs/*.json`, and config codecs (`KeyValueConfig`, `NamelistConfig`, `TopmodelConfig`).
- **Catalog changes:** draft with `bmi_setup/tools/probe_parameters.py`, then classify with `bmi_setup/tools/check_equivalence.py`. Don't hand-edit `set_value` statuses without rerunning the comparison.
- **Unit tests:** `python -m pytest bmi_setup/tests --ignore=bmi_setup/tests/integration`.
- **Integration tests:** `python -m pytest bmi_setup/tests/integration -m wrappers`. They need the wrappers plus the `PYMT_<KEY>_CONFIG` and `BMI_SETUP_FORCING_CSV` env vars; see `bmi_setup/README.md`.

## Known native quirks (documented, not fixed in the wrappers)

`common/README.md` covers these in detail. The main ones: CFE `get_value` copies only element 0 (use `get_value_ptr` for all layers), and CFE `get_value_at_indices` accepts only index 0. Noah-OWP's `get_value_ptr` always fails, and Fortran wrappers emulate `*_at_indices` through full `get_value`/`set_value` calls. Sac-SMA reports C-style type names. SMP `SetValue` and LASAM reallocate arrays, which invalidates earlier pointer views, so the wrappers query dtype and size from `get_var_type`/`get_var_itemsize`/`get_var_nbytes` on every call, never from grid size.

## Git hygiene

Commit source, config and docs only. Build output (`build/`, `dist/`, `*.egg-info`, `*.so`) and distribution tarballs (`*.tar.gz`, `*.tar.bz2`) are gitignored, even though `install.sh` reads tarballs from the working tree. Keep a single git repo at the root, with no nested `.git`.
