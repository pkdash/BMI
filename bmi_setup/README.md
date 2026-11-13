# bmi_setup

Set up and parameterize BMI models through their `pymt_*` Python wrappers.

`bmi_setup` is framework-neutral: it opens a model safely, says which
parameters it has, and edits the model's own config file. Running the model
inside a framework (for example, writing ngen's realization file and running
`ngen`) is the framework side's job. For ngen, that is `tools/ngen-bmi` in the
ngen repository.

```python
from bmi_setup import open_model, load_catalog, KeyValueConfig

with open_model("cfe", "cat-11223_bmi_config_cfe_pass.txt") as m:
    m.get("satdk")               # array([4.698e-06]); dtype and length from the library
    m.set("satdk", 2.0e-5)       # checked, converted safely, errors name model and variable
    m.parameters()               # catalog entries plus live values
    m.update()

with open_model("noah", "cat-11223.input", workdir="/path/to/ngen") as m:
    m.set("SMCMAX", 0.40)        # one value broadcast to every soil layer

cat = load_catalog("cfe")
cat["satdk"].config_key          # 'soil_params.satdk'
cat["satdk"].safe_to_set         # True: proven identical to a config edit

cfg = KeyValueConfig.read("cat-11223_bmi_config_cfe_pass.txt")
cfg.set("soil_params.satdk", 2.0e-5)    # keeps the "[m s-1]" unit and every other byte
cfg.write("edited.txt")
```

Needs Python 3.9+, `numpy<2`, and the wrapper for each model you open (built
from this repository; see each model's `QUICKSTART.md`). Install with
`pip install -e bmi_setup` from the repository root.

## Models

| Key | Wrapper | Config codec | Catalog |
|---|---|---|---|
| `cfe` | `pymt_cfe.CFE` | `KeyValueConfig` | yes |
| `noah` | `pymt_noah_owp.NOAH_OWP` | `NamelistConfig` | yes |
| `pet` | `pymt_pet.PET` | `KeyValueConfig` | yes (config only) |
| `topmodel` | `pymt_topmodel.TOPMODEL` | `TopmodelConfig` | yes |
| `lasam`, `sac_sma`, `sft`, `smp`, `snow17`, `ueb` | `pymt_<key>` | — | no |

Keys match the model keys in ngen's `tools/bmi-wrappers/wrappers.json`. Models
without a catalog can still be opened with `open_model`; they have no parameter
metadata. `Model` also accepts a wrapper class instead of a key.

## What `Model` / `open_model` guarantee

- **`finalize` always runs.** It runs when the `with` block exits (including on
  error), and also when a `Model` is garbage-collected while still initialized.
  The Fortran wrappers hold model handles in a fixed table of 2048 slots that
  only `finalize` frees. Without the safety net, the 2049th dropped instance
  makes every later `initialize` fail. C wrappers otherwise free the model
  struct without finalizing.
- **Working directory.** `initialize` runs with the current directory set to
  `workdir`, which defaults to the config file's directory. The previous
  directory is then restored. Models resolve relative paths in their config at
  `initialize`. `chdir` is process-wide, so don't initialize models from several
  threads at once; use processes for parallel runs.
- **Native chatter** printed during `initialize`/`finalize` goes to stderr.
- **`set`**:
  - A scalar is broadcast to the variable's length.
  - A sequence must match that length exactly, or `ValueError` is raised before
    any native call.
  - Values are converted only when it is safe (int→float, float64→float32); for
    example, float→int raises `TypeError`.
- **Catalog check.** When the model has a catalog, `initialize` checks every
  BMI parameter's name, dtype and length against the library and raises
  `CatalogMismatch` (after finalizing) if any differ. Pass
  `check_catalog=False` to skip it.

Native quirk, unchanged: CFE's `get_value` copies only element 0 of
multi-element variables (`common/README.md`). Use `m.bmi.get_value_ptr` for
those. All catalog parameters are scalars or Noah layers, and Noah's `get_value`
is complete.

## Parameter catalogs (`bmi_setup/catalogs/*.json`)

Each entry is keyed by its BMI name, or by its config key for config-only
parameters.

| Field | Meaning |
|---|---|
| `dtype`, `length` | as the library reports them. `length` may name a config key when it depends on the config (Noah: `"nsoil"`), or be `null` for a config-only list of any length |
| `units` | from the library or the config file, where known |
| `config_key` | the key in the model's own config (for its codec) that sets the same value, or `null` |
| `source` | where the value is read from when it is not the config (Noah: `SOILPARM.TBL:MAXSMC`) |
| `set_value` | see below |
| `note` | free text for reviewers |

`set_value` says how setting the parameter through BMI after `initialize`
compares with putting the same value in the config. This is what ngen's
`model_params` does.

| Value | Meaning |
|---|---|
| `equivalent` | every output at every step bit-identical over a 720-step test run |
| `unexercised` | changing it in the config changed nothing in the test run, so equivalence is unproven |
| `untested` | BMI-settable but not compared yet |
| `differs` | outputs differ: change it in the config instead |
| `none` | no BMI variable; change it in the config |

Current results:

- **CFE**
  - **Equivalent (13):** `b`, `satdk`, `satpsi`, `maxsmc`, `wltsmc`, `alpha_fc`,
    `Cgw`, `expon`, `refkdt`, `Kinf_nash_surface`, `retention_depth_nash_surface`,
    `a_Xinanjiang_inflection_point_parameter`, `x_Xinanjiang_shape_parameter`.
  - **Unexercised:** `Klf`, `Kn`, `slope`, `b_Xinanjiang_shape_parameter`.
  - **Differs:** `max_gw_storage`. CFE's `Set_value` does not rescale the
    current groundwater storage.
- **Noah-OWP**
  - **Equivalent** to a `SOILPARM.TBL` edit: `BEXP`, `SMCMAX`.
  - **Unexercised:** `DKSAT`, `REFKDT`.
  - **Untested:** the other 14, whose table sources are not mapped yet.
- **PET**
  - No BMI parameters. Physical and site parameters are changed in the config.
- **TOPMODEL**
  - **Equivalent:** `t0`, `szm`, `td`, `srmax`, `sr0`, `chv`, `rv`.
  - **Unexercised:** `xk0`, because TOPMODEL truncates the rate passed to
    `expinf`.
  - **Requires a TOPMODEL library with the `Get_var_nbytes` parameter fix.**
    Without it, stand-alone configs report one value per time step for each
    parameter, so the catalog check fails, as intended.

### Updating a catalog

```sh
# 1. draft from the live library (reviewed fields kept with --merge)
python bmi_setup/tools/probe_parameters.py cfe --config <cfg> --source <bmi_cfe.c> --merge --out draft.json
# 2. review, then copy the reviewed entries into bmi_setup/catalogs/cfe.json
# 3. classify every parameter with a config route (config edit vs set after initialize)
python bmi_setup/tools/check_equivalence.py cfe [--update]
```

The comparison cases are in `tests/integration/cases.py`. Each case uses ×1.5
of the current value unless listed in `OVERRIDES`, plus the config switches that
make a parameter matter at all (`BASE_EDITS`, e.g. the Xinanjiang scheme).

## Config codecs

`KeyValueConfig` (CFE, PET), `NamelistConfig` (Noah-OWP) and `TopmodelConfig`
(the `.run` file plus `params.dat`) share one interface: `read`, `keys`, `get`,
`set`, `to_text`, `write`.

- They change only the value of the keys you set. Comments, ordering, spacing,
  CFE unit suffixes, untouched lines and `\r\n` line endings are written back
  byte-for-byte.
- Numbers are written with `repr`, which reads back as exactly the same double
  in C and Fortran.
- Noah's parameter tables (`*.TBL`) are not covered.

## Tests

```sh
# unit tests: no models needed
python -m pytest bmi_setup/tests --ignore=bmi_setup/tests/integration

# integration tests against the real wrappers (same env vars as common/tests/test_native_models.py)
export PYMT_CFE_CONFIG=.../cat-11223_bmi_config_cfe_pass.txt
export PYMT_PET_CONFIG=.../cat-11223_pet_config.txt
export PYMT_NOAH_OWP_CONFIG=data/gauge_01073000/NOAH/cat-11223.input PYMT_NOAH_OWP_WORKDIR=/path/to/ngen
export PYMT_TOPMODEL_CONFIG=data/topmod.run PYMT_TOPMODEL_WORKDIR=/path/to/topmodel
export BMI_SETUP_FORCING_CSV=/path/to/ngen/data/forcing/cat-27_2015-12-01\ 00_00_00_2015-12-30\ 23_00_00.csv
python -m pytest bmi_setup/tests/integration -m wrappers -v
```

The integration suite does three things:
- checks every catalog against its library;
- reruns the config-vs-BMI comparison for every parameter whose status is
  `equivalent`, `unexercised` or `differs`, and fails if a status changes;
- checks the Noah lifecycle: repeatable runs, independent interleaved
  instances, and 2,100 instances dropped without `finalize`.

Models whose config variable is unset are skipped.
