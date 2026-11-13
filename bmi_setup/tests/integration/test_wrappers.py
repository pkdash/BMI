"""Integration tests against the real pymt_* wrappers and native libraries.

Run where the wrappers are installed, configured as described in ``cases.py``:

    python -m pytest tests/integration -m wrappers -v

A model whose ``PYMT_<KEY>_CONFIG`` is not set is skipped (CFE and Noah also
need ``BMI_SETUP_FORCING_CSV`` for the equivalence tests).

* every packaged catalog matches the library it is used with;
* every parameter whose catalog status is ``equivalent``, ``unexercised`` or
  ``differs`` still gets that status (the Phase 2 / M1 comparison, kept as a test);
* Noah lifecycle through ``Model``: repeatable runs, independent interleaved
  instances, and no leak of the Fortran wrapper's 2048 model slots when models
  are dropped without ``finalize``.
"""

import dataclasses
import gc

import numpy as np
import pytest

from bmi_setup import CatalogMismatch, Model, NamelistConfig, load_catalog, open_model
from bmi_setup.verify import compare_runs, run_steps
from cases import NoahSetup, cases_for, configured, make_setup

pytestmark = pytest.mark.wrappers

MODELS = ["cfe", "noah", "pet", "topmodel"]
CHECKED_STATUSES = ("equivalent", "unexercised", "differs")


def require(key):
    where = configured(key)
    if where is None:
        pytest.skip(f"PYMT_{key.upper()}_CONFIG not set")
    return where


@pytest.fixture(scope="session")
def scratch(tmp_path_factory):
    return tmp_path_factory.mktemp("bmi_setup")


@pytest.fixture(scope="session")
def setups(scratch):
    cache = {}

    def get(key):
        if key not in cache:
            cache[key] = make_setup(key, scratch)
        if cache[key] is None:
            pytest.skip(f"{key} not configured (PYMT_*_CONFIG / BMI_SETUP_FORCING_CSV)")
        return cache[key]
    return get


# ----------------------------------------------------------------- catalog vs library
@pytest.mark.parametrize("key", MODELS)
def test_catalog_matches_library(key):
    config, workdir = require(key)
    with open_model(key, config, workdir) as m:        # the catalog check runs here
        for p in m.catalog.bmi_parameters():
            value = m.get(p.name)
            assert value.dtype == np.dtype(p.dtype)
            m.set(p.name, value)                         # same value: must be accepted
            np.testing.assert_array_equal(m.get(p.name), value)


def test_stale_catalog_is_rejected():
    config, workdir = require("cfe")
    cat = load_catalog("cfe")
    cat.parameters["b"] = dataclasses.replace(cat["b"], length=2)
    m = Model("cfe", catalog=cat)
    with pytest.raises(CatalogMismatch, match="b: length is 1, catalog says 2"):
        m.initialize(config, workdir)
    assert not m.initialized


def test_layered_parameter_broadcast():
    config, workdir = require("noah")
    with open_model("noah", config, workdir) as m:
        n = m.var_length("SMCMAX")
        assert m.catalog["SMCMAX"].length == "nsoil"
        assert n == int(NamelistConfig.read(m.config).get("nsoil"))
        m.set("SMCMAX", 0.40)
        np.testing.assert_array_equal(m.get("SMCMAX"), np.full(n, 0.40, dtype=np.float32))
        with pytest.raises(ValueError, match="has 4 element"):
            m.set("SMCMAX", [0.4, 0.4])


# ----------------------------------------------------------------- equivalence
def _equivalence_ids():
    out = []
    for key in ("cfe", "noah", "topmodel"):
        for p in load_catalog(key).bmi_parameters():
            if p.set_value in CHECKED_STATUSES and (p.config_key or p.source):
                out.append(pytest.param(key, p.name, p.set_value, id=f"{key}-{p.name}"))
    return out


@pytest.mark.parametrize("key, param, expected", _equivalence_ids())
def test_equivalence(setups, key, param, expected):
    setup = setups(key)
    case = next(c for c in cases_for(setup) if c.param == param)
    result = setup.run(case)
    assert result.status == expected, (
        f"{key}.{param}: catalog says {expected}, measured {result.status} "
        f"(effect {result.effect:.3g}, config-vs-bmi {result.difference:.3g} "
        f"at {result.difference_output})")


# ----------------------------------------------------------------- Noah lifecycle
STEPS = 120


@pytest.fixture(scope="module")
def noah(setups):
    setup = setups("noah")
    assert isinstance(setup, NoahSetup)
    return setup, setup.write_config({}), setup.forcing()


def _noah_run(setup, cfg, forcing, smcmax=None):
    with setup.open(cfg) as m:
        if smcmax is not None:
            m.set("SMCMAX", smcmax)
        return run_steps(m, STEPS, forcing)


def test_noah_repeated_runs_are_identical(noah):
    setup, cfg, forcing = noah
    ref = _noah_run(setup, cfg, forcing)
    for _ in range(5):
        assert compare_runs(ref, _noah_run(setup, cfg, forcing))[2]


def test_noah_interleaved_instances_are_independent(noah):
    setup, cfg, forcing = noah
    solo_lo = _noah_run(setup, cfg, forcing, 0.40)
    solo_hi = _noah_run(setup, cfg, forcing, 0.434)
    assert not compare_runs(solo_lo, solo_hi)[2]
    with setup.open(cfg) as lo, setup.open(cfg) as hi:
        lo.set("SMCMAX", 0.40)
        hi.set("SMCMAX", 0.434)
        rec_lo, rec_hi = {o: [] for o in lo.output_names}, {o: [] for o in hi.output_names}
        for t in range(STEPS):
            for m, rec in ((lo, rec_lo), (hi, rec_hi)):
                for name, values in forcing.items():
                    m.set(name, values[t])
                m.update()
                for o in rec:
                    rec[o].append(np.asarray(m.get(o), dtype=float))
    assert compare_runs(solo_lo, {o: np.array(v) for o, v in rec_lo.items()})[2]
    assert compare_runs(solo_hi, {o: np.array(v) for o, v in rec_hi.items()})[2]


def test_noah_dropped_models_do_not_leak_slots(noah):
    """More instances than the Fortran wrapper has slots (2048), never finalized by hand."""
    setup, cfg, _ = noah
    for i in range(2100):
        m = Model("noah")
        m.initialize(cfg, setup.scratch)
        del m
        gc.collect()
    with setup.open(cfg) as m:                           # still able to create one
        assert m.initialized


def test_c_model_dropped_without_finalize():
    config, workdir = require("cfe")
    for _ in range(200):
        m = open_model("cfe", config, workdir)
        bmi = m.bmi
        del m
        gc.collect()
    with pytest.raises(RuntimeError):                    # the safety net finalized it
        bmi.update()
