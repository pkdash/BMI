"""Model lifecycle and access, against a pure-Python fake wrapper."""

import gc
import os

import numpy as np
import pytest

from bmi_setup import Catalog, CatalogMismatch, Model, open_model
from bmi_setup.verify import check_equivalence, compare_runs, run_steps
from fake_bmi import LOG, FakeBmi


@pytest.fixture
def config(tmp_path):
    p = tmp_path / "model.cfg"
    p.write_text("ok\n")
    return p


def fake_catalog(**overrides):
    params = {
        "scalar": {"dtype": "float64", "length": 1, "config_key": "scalar", "set_value": "equivalent"},
        "layers": {"dtype": "float32", "length": "nlayers", "set_value": "untested"},
        "only_in_config": {"config_key": "x", "set_value": "none"},
    }
    for name, fields in overrides.items():
        params[name] = {**params.get(name, {}), **fields}
    return Catalog.from_dict({"model": "fake", "parameters": params})


# ----------------------------------------------------------------- lifecycle
def test_context_manager_finalizes(config):
    with open_model(FakeBmi, config) as m:
        assert m.initialized
        bmi = m.bmi
    assert not m.initialized and bmi.finalized == 1


def test_finalize_on_error_inside_with(config):
    with pytest.raises(ZeroDivisionError):
        with open_model(FakeBmi, config) as m:
            bmi = m.bmi
            1 / 0
    assert bmi.finalized == 1


def test_double_finalize_is_a_noop(config):
    m = open_model(FakeBmi, config)
    m.finalize()
    m.finalize()
    assert m.bmi.finalized == 1


def test_garbage_collected_model_is_finalized(config):
    m = open_model(FakeBmi, config)
    bmi = m.bmi
    del m
    gc.collect()
    assert bmi.finalized == 1


def test_uninitialized_model_needs_no_finalize():
    m = Model(FakeBmi)
    bmi = m.bmi
    del m
    gc.collect()
    assert bmi.finalized == 0


def test_wrapper_is_created_only_when_needed(tmp_path, config):
    created = []

    class Counting(FakeBmi):
        def __init__(self):
            super().__init__()
            created.append(self)

    m = Model(Counting)
    assert created == [] and m.name == "Counting"
    with pytest.raises(FileNotFoundError):
        m.initialize(tmp_path / "missing.cfg")
    assert created == []                  # a Fortran wrapper would hold no slot
    m.initialize(config)
    assert len(created) == 1 and m.bmi is created[0]
    m.finalize()


def test_relative_config_without_workdir_is_relative_to_cwd(tmp_path, monkeypatch):
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "m.cfg").write_text("ok\n")
    monkeypatch.chdir(tmp_path)
    LOG.clear()
    with open_model(FakeBmi, "data/m.cfg") as m:
        assert m.config == tmp_path.resolve() / "data" / "m.cfg"
        assert m.workdir == tmp_path.resolve() / "data"
    assert LOG[0][2] == str(tmp_path.resolve() / "data")
    assert os.getcwd() == str(tmp_path.resolve())


def test_catalog_true_and_bad_catalog_arguments(config):
    with pytest.raises(TypeError, match="needs a model key"):
        Model(FakeBmi, catalog=True)
    with pytest.raises(TypeError, match="must be a Catalog"):
        Model(FakeBmi, catalog="cfe.json")
    assert Model(FakeBmi, catalog=False).catalog is None


def test_get_reads_every_element_through_pointer(config):
    class FirstElementOnly(FakeBmi):
        """Like native CFE: get_value fills only element 0."""
        def get_value(self, name, dest=None):
            out = super().get_value(name)
            out[1:] = np.nan
            return out

        def get_value_ptr(self, name):
            return self._vals[name]

    with open_model(FirstElementOnly, config) as m:
        m.set("layers", [0.1, 0.2, 0.3, 0.4])
        np.testing.assert_array_equal(m.get("layers"),
                                      np.array([0.1, 0.2, 0.3, 0.4], dtype=np.float32))
        v = m.get("layers")
        v[:] = 9                                  # a copy, not the model's memory
        assert m.get("layers")[0] == np.float32(0.1)

    class NoPointer(FakeBmi):                     # like Noah-OWP: the pointer always fails
        def get_value_ptr(self, name):
            raise NotImplementedError

    with open_model(NoPointer, config) as m:
        assert m.get("layers").shape == (4,)


def test_initialize_runs_in_workdir_and_restores_cwd(config, tmp_path):
    before = os.getcwd()
    LOG.clear()
    with open_model(FakeBmi, "model.cfg", workdir=tmp_path) as m:
        assert os.getcwd() == before
        assert m.config == tmp_path / "model.cfg" and m.workdir == tmp_path.resolve()
    assert LOG[0] == ("initialize", id(m.bmi), str(tmp_path.resolve()))


def test_workdir_defaults_to_config_directory(config, tmp_path, monkeypatch):
    monkeypatch.chdir("/")
    with open_model(FakeBmi, config) as m:
        assert m.workdir == tmp_path.resolve()


def test_cwd_restored_after_failed_initialize(tmp_path):
    bad = tmp_path / "bad.cfg"
    bad.write_text("fail\n")
    before = os.getcwd()
    with pytest.raises(RuntimeError, match=r"FakeBmi: initialize\(.*bad config"):
        open_model(FakeBmi, bad)
    assert os.getcwd() == before


def test_missing_config_is_reported_before_initialize(tmp_path):
    with pytest.raises(FileNotFoundError, match="nope.cfg"):
        open_model(FakeBmi, tmp_path / "nope.cfg")


def test_initialize_twice_raises(config):
    with open_model(FakeBmi, config) as m:
        with pytest.raises(RuntimeError, match="already initialized"):
            m.initialize(config)


def test_chatter_goes_to_stderr(config, capfd):
    with open_model(FakeBmi, config):
        pass
    out, err = capfd.readouterr()
    assert "model chatter" not in out and "model chatter" in err


# ----------------------------------------------------------------- get / set
def test_get_returns_a_copy_with_library_dtype(config):
    with open_model(FakeBmi, config) as m:
        v = m.get("layers")
        assert v.dtype == np.float32 and v.shape == (4,)
        v[:] = 9
        assert m.get("layers")[0] == np.float32(0.3)
        assert m.var_length("layers") == 4 and m.var_dtype("count") == np.int32


def test_set_broadcasts_scalars(config):
    with open_model(FakeBmi, config) as m:
        m.set("layers", 0.4)
        np.testing.assert_array_equal(m.get("layers"), np.full(4, 0.4, dtype=np.float32))
        m.set("scalar", 2)                      # int -> float is safe
        assert m.get("scalar")[0] == 2.0
        m.set("scalar", np.array([3.0]))
        assert m.get("scalar")[0] == 3.0


def test_set_sequence_must_match_length(config):
    with open_model(FakeBmi, config) as m:
        m.set("layers", [0.1, 0.2, 0.3, 0.4])
        with pytest.raises(ValueError, match="'layers' has 4 element"):
            m.set("layers", [0.1, 0.2])
        with pytest.raises(ValueError):
            m.set("scalar", [1.0, 2.0])


def test_set_unsafe_cast_is_rejected_with_context(config):
    with open_model(FakeBmi, config) as m:
        with pytest.raises(TypeError, match=r"FakeBmi: set_value\('count'\)"):
            m.set("count", 2.5)
        with pytest.raises(TypeError, match="cannot set"):
            m.set("scalar", {"a": 1})


def test_unknown_variable_names_model_and_variable(config):
    with open_model(FakeBmi, config) as m:
        with pytest.raises(RuntimeError, match=r"FakeBmi: get_var_itemsize\('nope'\)"):
            m.set("nope", 1.0)
        assert not m.is_var("nope") and m.is_var("scalar")


def test_access_after_finalize_raises(config):
    m = open_model(FakeBmi, config)
    m.finalize()
    with pytest.raises(RuntimeError, match="needs an initialized model"):
        m.get("scalar")
    with pytest.raises(RuntimeError):
        m.set("scalar", 1.0)
    with pytest.raises(RuntimeError):
        m.update()


# ----------------------------------------------------------------- catalog
def test_catalog_check_passes_and_parameters_read_live(config):
    with open_model(FakeBmi, config, catalog=fake_catalog()) as m:
        params = m.parameters()
        assert params["scalar"]["value"][0] == 1.5
        assert "value" not in params["only_in_config"]
        assert m.parameter("scalar").safe_to_set


@pytest.mark.parametrize("override, message", [
    ({"scalar": {"dtype": "float32"}}, "dtype is float64, catalog says float32"),
    ({"scalar": {"length": 3}}, "length is 1, catalog says 3"),
    ({"ghost": {"dtype": "float64", "set_value": "equivalent"}}, "ghost: not a variable"),
])
def test_catalog_mismatch_raises_and_finalizes(config, override, message):
    m = Model(FakeBmi, catalog=fake_catalog(**override))
    with pytest.raises(CatalogMismatch, match=message):
        m.initialize(config)
    assert not m.initialized and m.bmi.finalized == 1


def test_catalog_check_can_be_skipped(config):
    with open_model(FakeBmi, config, catalog=fake_catalog(ghost={"dtype": "float64",
                                                                 "set_value": "untested"}),
                    check_catalog=False) as m:
        assert m.initialized


# ----------------------------------------------------------------- verify
def test_run_steps_and_compare(config):
    with open_model(FakeBmi, config) as m:
        a = run_steps(m, 3, {"scalar": [1.0, 2.0, 3.0]})
    assert a["q_out"].shape == (3, 1)
    np.testing.assert_allclose(a["q_out"][:, 0], np.cumsum([1.2, 2.4, 3.6]), rtol=1e-6)
    assert compare_runs(a, a) == (0.0, None, True)
    b = {"q_out": a["q_out"] * 2}
    rel, where, same = compare_runs(a, b)
    assert where == "q_out" and not same and rel > 0
    nan = {"q_out": np.array([[np.nan]])}
    assert compare_runs(nan, {"q_out": np.array([[np.nan]])})[2]
    with pytest.raises(ValueError, match="3 steps"):
        with open_model(FakeBmi, config) as m:
            run_steps(m, 3, {"scalar": [1.0]})


def test_check_equivalence_statuses(tmp_path):
    base = tmp_path / "base.cfg"
    base.write_text("ok\n")

    def opener():
        return open_model(FakeBmi, base)

    r = check_equivalence(opener, opener, "scalar", 3, value=1.5)
    assert r.status == "unexercised"

    class Edited(FakeBmi):
        def initialize(self, config):
            super().initialize(config)
            self._vals["scalar"][:] = 2.0

    # The edited config holds 2.0, but BMI sets 4.0: the runs differ.
    r = check_equivalence(opener, lambda: open_model(Edited, base), "scalar", 3, value=4.0)
    assert r.status == "differs" and r.difference_output == "q_out"

    # The config edit changes nothing, but setting through BMI does: that is a
    # difference, not an unexercised parameter.
    r = check_equivalence(opener, opener, "scalar", 3, value=4.0)
    assert r.effect == 0 and r.status == "differs"


def test_equivalent_when_bmi_matches_config(tmp_path):
    class Edited(FakeBmi):
        def initialize(self, config):
            super().initialize(config)
            self._vals["layers"][:] = 0.5

    base = tmp_path / "base.cfg"
    base.write_text("ok\n")
    r = check_equivalence(lambda: open_model(FakeBmi, base), lambda: open_model(Edited, base),
                          "layers", 3)
    assert r.status == "equivalent" and r.difference == 0 and r.effect > 0
