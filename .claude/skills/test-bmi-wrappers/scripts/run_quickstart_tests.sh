#!/usr/bin/env bash
# Build, install and test the pymt_* BMI wrappers the way each <MODEL>/QUICKSTART.md
# documents it, inside the model's own Docker image, on a scratch copy of the model
# directory (the checkout is never modified).
#
# Per model:
#   1. docker build <MODEL>/Dockerfile                       (QUICKSTART step 1)
#   2. docker run with the scratch copy mounted at /workspace/user  (step 2)
#   3. model-specific native build, if QUICKSTART has one     (NOAH_OWP step 3)
#   4. ./regen_and_build.sh  (babelize init + post_babelize_patch.sh + uv build)
#   5. pip install "numpy<2"; pip install -e . --no-build-isolation
#      python -c "from pymt_x import X"; X().get_component_name(); var names/types
#   6. (unless --no-contract) common/tests/test_native_models.py against the real
#      native library, using a sample config shipped in the image's model repo.
#
# Usage (from anywhere inside the repo):
#   run_quickstart_tests.sh [--out DIR] [--src-root DIR] [--no-contract] [--no-cache] [MODEL ...]
# --src-root takes the <MODEL>/ directories from another tree instead of this checkout,
# e.g. `git archive main CFE | tar -x -C /tmp/main` then --src-root /tmp/main, to check
# whether a failure predates the current changes (common/ still comes from this checkout).
# MODEL is a directory name (CFE, PET, SOIL-FREEZE-THAW, ...) or a key (SFT, SMP).
# With no MODEL, all ten wrappers are tested.  Exit status is non-zero if any fails.
set -uo pipefail

REPO="$(git -C "$(dirname -- "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
OUT="${BMI_QS_OUT:-/tmp/bmi-wrapper-tests}/$(date +%Y%m%d-%H%M%S)"
CONTRACT=1
SRC_ROOT=""
NO_CACHE=""
MODELS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --src-root) SRC_ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    --no-contract) CONTRACT=0; shift ;;
    --no-cache) NO_CACHE="--no-cache"; shift ;;
    -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) MODELS+=("$1"); shift ;;
  esac
done

ALL_MODELS=(CFE PET TOPMODEL SOIL-FREEZE-THAW SOIL-MOISTURE-PROFILES LASAM UEB NOAH_OWP SAC_SMA SNOW17)
[[ ${#MODELS[@]} -eq 0 ]] && MODELS=("${ALL_MODELS[@]}")

# Per-model settings (bash 3.2 compatible: no associative arrays).
#   KEY       test key used by common/tests/test_native_models.py (PYMT_<KEY>_CONFIG)
#   CONFIG    sample BMI config inside the image (contract tests)
#   WORKDIR   directory to chdir into before initialize (relative paths in CONFIG)
#   NATIVE    shell run in the container before step 4 (QUICKSTART native-build step)
#   PREP      shell run before the contract tests (e.g. unpack a standalone test case)
model_settings() {
  KEY=""; CONFIG=""; WORKDIR=""; NATIVE=""; PREP=""
  case "$1" in
    CFE|cfe) DIR=CFE; KEY=CFE
      CONFIG=/workspace/cfe/configs/cfe_config_laramie_pass_aet_rz.txt; WORKDIR=/workspace/cfe ;;
    PET|pet) DIR=PET; KEY=PET
      CONFIG=/workspace/evapotranspiration/configs/pet_config_bmi.txt; WORKDIR=/workspace/evapotranspiration ;;
    TOPMODEL|topmodel) DIR=TOPMODEL; KEY=TOPMODEL
      CONFIG=/workspace/topmodel/data/topmod.run; WORKDIR=/workspace/topmodel ;;
    SOIL-FREEZE-THAW|SFT|sft) DIR=SOIL-FREEZE-THAW; KEY=SFT
      CONFIG=/workspace/sft/configs/laramie_config_standalone.txt; WORKDIR=/workspace/sft ;;
    SOIL-MOISTURE-PROFILES|SMP|smp) DIR=SOIL-MOISTURE-PROFILES; KEY=SMP
      CONFIG=/workspace/smp/configs/config_layered.txt; WORKDIR=/workspace/smp ;;
    LASAM|lasam) DIR=LASAM; KEY=LASAM
      CONFIG=/workspace/LGAR-C/configs/config_lasam_Phillipsburg.txt; WORKDIR=/workspace/LGAR-C ;;
    UEB|ueb) DIR=UEB; KEY=UEB
      CONFIG=/workspace/ueb_bmi/examples/TWDEF_onecell/control.dat; WORKDIR=/workspace/ueb_bmi/examples/TWDEF_onecell ;;
    NOAH_OWP|noah_owp) DIR=NOAH_OWP; KEY=NOAH_OWP
      CONFIG=/workspace/noah-owp-modular/run/namelist.input; WORKDIR=/workspace/noah-owp-modular/run
      # NOAH_OWP/QUICKSTART.md step 3: build Noah-OWP + libsurfacebmi.so inside the container.
      NATIVE='cd /workspace/noah-owp-modular
printf " COMPILERF90    =       gfortran\n NETCDFMOD      =       -I/opt/conda/include\n NETCDFLIB      =       -L/opt/conda/lib -lnetcdf -lnetcdff\n F90FLAGS       =       -g -fbacktrace -fPIC\n" > user_build_options
make clean && make testBMI
gfortran -shared -fPIC -o /workspace/noah-owp-modular/libsurfacebmi.so bmi/bmi.o bmi/bmi_noahowp.o src/*.o -L/opt/conda/lib -lnetcdf -lnetcdff
export LD_LIBRARY_PATH=/workspace/noah-owp-modular:/opt/conda/lib:${LD_LIBRARY_PATH:-}' ;;
    SAC_SMA|sac_sma) DIR=SAC_SMA; KEY=SAC_SMA
      # Standalone test case (ngen_files/*.namelist.input assumes an ngen checkout layout).
      CONFIG=/workspace/sac-sma/test_cases/ex1/run/namelist.bmi.HHWM8; WORKDIR=/workspace/sac-sma/test_cases/ex1/run
      # Sac-SMA declares start_datehr/end_datehr as character(len=10) but its shipped
      # namelists leave them unquoted, which gfortran rejects ("Missing quote"), so quote
      # them in the throwaway container (native config issue, not a wrapper issue).
      PREP='mkdir -p /workspace/sac-sma/test_cases/ex1/output /workspace/sac-sma/test_cases/ex1/state
sed -i -E "s/^( *(start|end)_datehr *= *)([0-9]{10})/\1\"\3\"/" /workspace/sac-sma/test_cases/ex1/run/namelist.bmi.HHWM8' ;;
    SNOW17|snow17) DIR=SNOW17; KEY=SNOW17
      # Standalone test case shipped as test_cases/ex1.tgz (configs/*.namelist.input assumes ngen paths).
      CONFIG=/tmp/snow17_ex1/ex1/run/namelist.bmi.HHWM8; WORKDIR=/tmp/snow17_ex1/ex1/run
      PREP='mkdir -p /tmp/snow17_ex1 && tar xzf /workspace/snow17/test_cases/ex1.tgz -C /tmp/snow17_ex1 && mkdir -p /tmp/snow17_ex1/ex1/output' ;;
    *) return 1 ;;
  esac
}

mkdir -p "$OUT"
echo "Results and logs: $OUT"
SUMMARY="$OUT/summary.txt"
printf '%-24s %-8s %-11s %s\n' MODEL IMAGE QUICKSTART CONTRACT > "$SUMMARY"
FAILED=0

for m in "${MODELS[@]}"; do
  if ! model_settings "$m"; then
    echo "unknown model: $m" >&2; FAILED=1; continue
  fi
  SRC="${SRC_ROOT:-$REPO}/$DIR"
  WORK="$OUT/$DIR"
  LOG="$OUT/$DIR.log"
  TAG="bmi-qs-$(echo "$DIR" | tr 'A-Z_' 'a-z-')"
  PKG="$(basename "$(ls -d "$SRC"/pymt_*/ | head -1)")"
  CLASS="$(sed -n 's/^\[library\.\(.*\)\]/\1/p' "$SRC/babel.toml" | head -1)"
  echo
  echo "=== $DIR  (package $PKG, class $CLASS, image $TAG)"

  rm -rf "$WORK"          # only this run's scratch copy under $OUT
  mkdir -p "$WORK"
  cp -R "$SRC/." "$WORK/"

  echo "--- [1] docker build" | tee "$LOG"
  if ! docker build --pull ${NO_CACHE} -t "$TAG" "$WORK" >> "$LOG" 2>&1; then
    echo "    image build FAILED (see $LOG)"
    printf '%-24s %-8s %-11s %s\n' "$DIR" FAIL - - >> "$SUMMARY"; FAILED=1; continue
  fi

  RUN_CONTRACT=$CONTRACT
  [[ -z "$CONFIG" ]] && RUN_CONTRACT=0

  echo "--- [2-6] docker run (quickstart + contract=$RUN_CONTRACT)"
  docker run --rm \
    -v "$WORK":/workspace/user \
    -v "$REPO/common":/workspace/common:ro \
    -e "PYMT_${KEY}_CONFIG=$CONFIG" -e "PYMT_${KEY}_WORKDIR=$WORKDIR" \
    -e PKG="$PKG" -e CLASS="$CLASS" -e KEY="$KEY" -e CONFIG="$CONFIG" \
    -e NATIVE="$NATIVE" -e PREP="$PREP" -e RUN_CONTRACT="$RUN_CONTRACT" \
    -w /workspace/user "$TAG" bash -c '
set -eo pipefail
if [[ -n "$NATIVE" ]]; then echo "--- [3] native build (QUICKSTART)"; eval "$NATIVE"; fi
echo "--- [4] regen_and_build.sh"
cd /workspace/user
sed -i "s/\r//" *.sh; chmod +x *.sh
./regen_and_build.sh
echo "--- [5] install + import"
cd "/workspace/user/$PKG"
python -m pip install -q "numpy<2"
python -m pip install -q -e . --no-build-isolation
python -c "from $PKG import $CLASS; print(\"$PKG import OK\")"
python -c "from $PKG import $CLASS; m=$CLASS(); print(m.get_component_name())"
python -c "
from $PKG import $CLASS
m = $CLASS()
print(\"inputs :\", m.get_input_var_names())
print(\"outputs:\", m.get_output_var_names())
for n in (m.get_output_var_names() + m.get_input_var_names())[:3]:
    print(\"type   :\", n, m.get_var_type(n))
"
echo "@@QUICKSTART_OK"
set +e
if [[ "$RUN_CONTRACT" == 1 ]]; then
  echo "--- [6] contract tests"
  if [[ -n "$PREP" ]]; then eval "$PREP" || echo "PREP failed"; fi
  if [[ ! -f "$CONFIG" ]]; then echo "@@CONTRACT=NOCONFIG $CONFIG"; exit 0; fi
  python -m pip install -q pytest
  cd /tmp
  python -X faulthandler -m pytest -p no:cacheprovider -v -rs \
    /workspace/common/tests/test_native_models.py -k "$KEY"
  rc=$?
  echo "@@CONTRACT_RC=$rc"
fi
' >> "$LOG" 2>&1

  if grep -q '^@@QUICKSTART_OK' "$LOG"; then QS=PASS; else QS=FAIL; FAILED=1; fi
  if [[ $QS == FAIL ]]; then CT=-
  elif [[ $RUN_CONTRACT == 0 ]]; then CT=skipped
  elif grep -q '^@@CONTRACT=NOCONFIG' "$LOG"; then CT="no-config"; FAILED=1
  else
    rc="$(sed -n 's/^@@CONTRACT_RC=//p' "$LOG")"
    tally="$(grep -E '^=+ .*(passed|failed|error).* =+$' "$LOG" | tail -1 | sed 's/=//g; s/^ *//; s/ *$//')"
    if [[ "$rc" == 0 ]]; then CT="PASS ($tally)"; else CT="FAIL rc=${rc:-crash} ($tally)"; FAILED=1; fi
  fi
  printf '%-24s %-8s %-11s %s\n' "$DIR" OK "$QS" "$CT" >> "$SUMMARY"
  echo "    quickstart: $QS   contract: $CT   (log: $LOG)"
done

echo
cat "$SUMMARY"
echo
echo "Logs: $OUT/<MODEL>.log   Scratch copies: $OUT/<MODEL>/"
exit $FAILED
