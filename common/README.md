# Shared BMI wrapper layer

Everything in this directory is shared by the ten `pymt_*` wrappers. It
guarantees that the runtime value-exchange part of BMI (`get_value`,
`get_value_ptr`, `set_value`, `get_value_at_indices`, `set_value_at_indices`)
behaves the same way for C, C++ and Fortran models.

| File | Purpose |
| --- | --- |
| `templates/c.pyx.in` | Wrapper for C models that register a `Bmi` function table (CFE, PET, TOPMODEL) |
| `templates/cxx.pyx.in` | Wrapper for C++ `bmi::Bmi` subclasses (SFT, SMP, LASAM, UEB) |
| `templates/fortran.pyx.in` | Wrapper over Babelizer's Fortran interop layer (NOAH_OWP, SAC_SMA, SNOW17) |
| `bmi_arrays.py` | Pure-NumPy rules: dtype resolution, buffer validation, safe casting |
| `bmi_ptr.pxi` | Turns a native pointer into a NumPy view that keeps the model alive |
| `install_wrapper.sh` | Vendored as `<MODEL>/wrapper/install.sh`; run by `post_babelize_patch.sh` |
| `render_wrappers.py` | Renders `<MODEL>/wrapper/` and `pymt_<model>/.../lib/` for every model |
| `tests/` | Unit tests (no models needed) and the native contract suite |

## Why it exists

Every native C/C++ `get_value`/`set_value` copies exactly
`get_var_nbytes(name)` bytes, and the element type is whatever
`get_var_type`/`get_var_itemsize` report. The Babelizer-generated and
hand-written wrappers passed `ndarray.data` straight through without checking
dtype, size or contiguity. This caused silent corruption and out-of-bounds
reads and writes, for example:

* `set_value` with an int64 array on a `double` variable wrote `1e-323`.
* A 1-element array for CFE's 4-layer `soil_moisture_profile` over-read the heap.
* C wrappers viewed every `get_value_ptr` as float64, so CFE's `int`
  `SURF_RUNOFF_SCHEME` read as `3.9e+180`.
* C wrappers sized `get_value_ptr` views by grid size, which truncated
  `soil_moisture_profile` (grid size 1, n_soil_layers values) and failed for
  CFE's calibration parameters, which have no grid.
* Fortran wrappers mapped `real` to float32 even when the model reports 8-byte items.
* C wrappers had no `*_at_indices`, and C++ wrappers rejected default int64 index arrays.
* Views from `get_value_ptr` did not keep the model alive.

## Behavior of the generated wrappers

* **Layout.** dtype comes from the type name plus the native item size
  (`resolve_dtype`). The length is `nbytes // itemsize`. Both are queried on
  every call, because some models resize variables at run time (LASAM wetting
  fronts, SMP `ResetSize`).
* **`get_value(name, dest=None)`.** Without `dest`, it allocates a 1-D array,
  pre-filled with NaN for floating-point variables, so that elements the
  native code does not write cannot pass for real values.
  A supplied `dest` must have exactly the variable's dtype, be C-contiguous and
  writeable, and hold at least `count` items. Otherwise it raises
  `TypeError`/`ValueError`. It never converts, since `dest` is filled in place.
* **`set_value(name, src)`.** It accepts arrays, lists and scalars. Conversion
  uses NumPy `same_kind` casting (int→float, float64→float32), plus
  integer→integer when every value fits. Float→int and other lossy kind
  changes raise `TypeError`. The size must match exactly (`ValueError`).
* **`*_at_indices`.** Indices may be any integer array-like and are
  bounds-checked. On Fortran models they are emulated with a full
  `get_value`/`set_value`, because the interop layer has no indexed entry
  points.
* **`get_value_ptr(name)`.** It returns a writeable view whose `.base` is the
  model object. The view becomes invalid after `finalize()` and after any
  native call that reallocates the variable, so fetch a new one after those.
  Fortran models that do not expose pointers raise `NotImplementedError`.
* **`get_var_type(name)`.** It returns the NumPy dtype name (`'float64'`,
  `'int32'`, ...), as before. Only type and item size are queried, so it also
  works before `initialize()`. Fortran 4-byte `logical` maps to `int32`,
  because NumPy bools are 1 byte.
* **Lifecycle.** Value accessors and `update`/`update_until` raise
  `RuntimeError` before `initialize()` and after `finalize()`, instead of
  dereferencing uninitialized or released model state. A second `finalize()`
  is a no-op.

### Native behavior that is documented, not changed

* CFE `Get_value` copies only element 0 (it calls `Get_value_at_indices` with
  `{0}`, length 1). `get_value("soil_moisture_profile")` therefore returns
  layer 0 followed by NaN. Use `get_value_ptr` to read all layers; `set_value`
  writes all of them.
* CFE `get_value_at_indices` only accepts index 0.
* CFE `get_var_grid` fails for calibration parameters, and `get_grid_shape`
  is not implemented.
* Noah-OWP's Fortran `get_value_ptr` returns `BMI_FAILURE` for every
  variable. Sac-SMA reports C-style type names (`"double"`), which the
  Fortran interop's pointer path does not recognise.
* SMP `SetValue` reallocates the wetting-front arrays, which invalidates
  earlier pointer views.

## Changing the wrappers

1. Edit a template, `bmi_arrays.py` or `bmi_ptr.pxi`. Per-model options that
   `babel.toml` cannot express (C++ namespace, string encoding, extra
   model-specific methods) live in `MODELS` in `render_wrappers.py`.
2. Run `python common/render_wrappers.py`. It needs Python 3.11+, or
   `pip install tomli`. It rewrites `<MODEL>/wrapper/*` and the committed
   `pymt_<model>/pymt_<model>/lib/*`.
3. Commit both. `python common/render_wrappers.py --check` fails if anything
   is stale.

`<MODEL>/wrapper/` is vendored inside each model directory because the
Docker workflow mounts only that directory. `post_babelize_patch.sh` runs
`wrapper/install.sh`, which copies the sources into the freshly generated
package after `babelize init`. No change to
`babel.toml` is needed: Babelizer has no options that affect this code.

## Tests

To run every wrapper through its QUICKSTART.md flow in Docker (image build,
`regen_and_build.sh`, `pip install -e .`, import checks) plus the contract
suite below, on scratch copies, use the Claude Code skill
`/test-bmi-wrappers`, or run its script directly:

```sh
.claude/skills/test-bmi-wrappers/scripts/run_quickstart_tests.sh [--no-contract] [MODEL ...]
```

Unit tests (no native libraries needed):

```sh
python -m pytest common/tests/test_bmi_arrays.py
```

Contract tests against the real native libraries. Run them wherever the
wrappers are installed (a model's Docker image with the repository mounted,
or JupyterHub). Each model runs only when its config is given:

```sh
export PYMT_CFE_CONFIG=/path/to/cfe/configs/cfe_config_laramie_pass_aet_rz.txt
export PYMT_SFT_CONFIG=/path/to/SoilFreezeThaw/configs/laramie_config_standalone.txt
export PYMT_SFT_WORKDIR=/path/to/SoilFreezeThaw   # chdir for relative paths in the config
python -X faulthandler -m pytest common/tests/test_native_models.py -v
```

Keys: `CFE`, `PET`, `TOPMODEL`, `SFT`, `SMP`, `LASAM`, `UEB`, `NOAH_OWP`,
`SAC_SMA`, `SNOW17`. For every exchange item the suite checks:

* metadata consistency;
* that `get_value` allocation and a supplied `dest` agree;
* that bad `dest`/`src` buffers are rejected and do not crash;
* `get_value_ptr` liveness and ownership;
* `set_value` and `*_at_indices` round trips with arrays, lists and scalars;
* lifecycle guards.

It also has regressions for the CFE findings above and for Noah's missing
pointers. The CSDMS conformance suite still applies:
`bmi-test pymt_cfe.bmi:CFE --root-dir <dir> --config-file <file>`.
