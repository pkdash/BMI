---
name: test-bmi-wrappers
description: Build, install and test the pymt_* BMI wrappers exactly as each <MODEL>/QUICKSTART.md documents (Docker image build, regen_and_build.sh, pip install -e . --no-build-isolation, import/get_component_name checks), plus the native BMI contract suite, on scratch copies so the checkout is untouched. Use after changing anything that affects the wrappers (common/, templates, post_babelize_patch.sh, setup.py, Dockerfiles, babel.toml). Optional args: model names (CFE, PET, TOPMODEL, SFT, SMP, LASAM, UEB, NOAH_OWP, SAC_SMA, SNOW17), --no-contract, --no-cache.
---

# Test the BMI wrappers the QUICKSTART way

Each `<MODEL>/QUICKSTART.md` documents how a developer builds and checks a
wrapper inside that model's Docker image. This skill runs those same steps for
every wrapper (or the ones requested), then exercises the BMI value accessors
against the real native library with `common/tests/test_native_models.py`.

The runner is `.claude/skills/test-bmi-wrappers/scripts/run_quickstart_tests.sh`.
For each model it:

1. copies `<MODEL>/` into a scratch directory (the checkout is never written to);
2. `docker build`s the model's `Dockerfile` (QUICKSTART step 1);
3. starts the container with the copy mounted at `/workspace/user` (step 2);
4. runs any native-build step the QUICKSTART requires inside the container
   (NOAH_OWP step 3: `make testBMI` + link `libsurfacebmi.so`);
5. runs `./regen_and_build.sh` (`babelize init` → `post_babelize_patch.sh` → `uv build`);
6. runs `pip install "numpy<2"`, `pip install -e . --no-build-isolation`, the
   QUICKSTART `python -c` import and `get_component_name()` checks, and prints
   the variable names and a few `get_var_type` results;
7. unless `--no-contract`: runs the contract suite with a sample config that
   ships in the image's model repo (`initialize`, every exchange item through
   `get_value`/`get_value_ptr`/`set_value`/`*_at_indices`, lifecycle guards).

## How to run it

1. **Pick the scope.** Use the models the user named; otherwise test all ten.
   If the user only changed one language family, still prefer all ten unless
   they ask for less — the families share `common/`.
2. **Check Docker** with `docker info --format '{{.ServerVersion}}'`. If it is
   not running, stop and tell the user.
3. **Run the script in the background** (first image builds take minutes; the
   Fortran images the longest), writing into the session scratchpad:

   ```bash
   .claude/skills/test-bmi-wrappers/scripts/run_quickstart_tests.sh \
     --out "<scratchpad>/bmi-wrapper-tests" [--no-contract] [--no-cache] [MODEL ...]
   ```

   Pass `--no-cache` only when the user asks for a clean image rebuild, or
   when a Dockerfile/upstream change must be picked up. It reuses images
   (tagged `bmi-qs-<model>`) otherwise.
4. **Wait for the completion notification** — do not poll. Then read
   `<out>/summary.txt`. For any failure, read the end of `<out>/<MODEL>.log`
   and find the first real error (`grep -nE 'Error|error:|FAILED|Traceback'`).

## Reporting

Give the user a table: model | image build | QUICKSTART (steps 1–5) |
contract tests (pass count). Then, for each failure:

- the step that failed and the first real error message, quoted;
- whether the failure is in the wrapper code, the patch/build scripts, the
  Dockerfile/environment, the sample config, or the native library;
- **whether it predates the current changes**: export the model from the
  default branch with `git archive main <MODEL> | tar -x -C <scratch>/main_src`
  and re-run with `--src-root <scratch>/main_src --out <scratch>/main_run <MODEL>`,
  then say whether `main` fails identically. For a QUICKSTART failure that is
  conclusive. For a contract failure, the suite in `common/tests` targets the
  new wrapper API, so reproduce the specific failing call with a small Python
  probe against both builds instead of comparing whole suite results.

Before concluding that the environment is broken, re-read that model's
QUICKSTART.md and confirm every documented step was run; add any missing
native-build step to `model_settings` in the script rather than skipping it.

## Rules

- **Never change repository code to make a failing test pass.** Report the
  problem and the fix you propose, and ask the user for permission first.
  This covers wrappers, templates, `common/`, patch scripts, Dockerfiles,
  QUICKSTART docs and the runner itself.
- Never run the wrappers in the user's checkout: the regeneration step deletes
  and recreates `pymt_<model>/`, and builds write `build/`, `dist/`, `.so`
  and `.c/.cpp` files. Always use `--out` in the scratchpad.
- Do not delete anything outside the run's `--out` directory. Docker images
  are kept for reuse; mention `docker image rm bmi-qs-<model>` if the user
  wants the space back, but do not run it unasked.
- A contract result of `no-config` means the sample config path in
  `model_settings` no longer exists in the image (upstream moved it). Report
  it; do not guess another path silently.

## Known native behavior (not wrapper failures)

These are documented in `common/README.md`; the contract suite already
accounts for them:

- CFE `Get_value` copies only element 0; CFE grid functions fail for some
  variables (so `bmi-test` stage 3 has two pre-existing failures).
- Noah-OWP never exposes `get_value_ptr` (the wrapper raises
  `NotImplementedError`); pointer tests are skipped for it.
- SMP `SetValue` reallocates wetting-front arrays.
- **UEB contract run aborts with `double free or corruption`** in
  `test_set_value_round_trip`. Native bug: for time-series forcings (`Prec`,
  `Ta` in the TWDEF_onecell example) `GetValuePtr` returns
  `&tsvar[i][0][get_istep() - 1]`, i.e. index -1 before the first `update()`,
  so `SetValue` writes before the array and the heap corruption surfaces in the
  destructor. Reproduces identically with the pre-change wrapper on `main`;
  setting the forcing after one `update()` is fine. Report it as pre-existing
  unless the failure moves elsewhere.
- Sac-SMA's shipped namelists leave `start_datehr`/`end_datehr` unquoted
  although they are `character(len=10)`; gfortran rejects them. The runner's
  `PREP` quotes them inside the throwaway container.
- SAC_SMA and SNOW17 use their standalone test cases (`test_cases/ex1`); the
  `ngen_files/` / `configs/` namelists assume an ngen checkout layout.

## Extending

To add a model, add a `case` to `model_settings` in the script with its
directory, contract-test key (from `WRAPPERS` in
`common/tests/test_native_models.py`), a sample config inside the image, the
working directory for relative paths, and any native-build commands its
QUICKSTART requires.
