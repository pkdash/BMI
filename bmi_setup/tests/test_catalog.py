"""Catalog files: schema rules, and the packaged catalogs are valid."""

import json

import pytest

from bmi_setup import MODELS, Catalog, Parameter, load_catalog
from bmi_setup.catalog import CATALOG_DIR, STATUSES
from bmi_setup.config_files import TopmodelConfig

CATALOGED = [k for k, s in MODELS.items() if s.catalog]


def test_parameter_rules():
    with pytest.raises(ValueError, match="set_value"):
        Parameter("x", set_value="maybe", dtype="float64")
    with pytest.raises(ValueError, match="config_key"):
        Parameter("x", set_value="none")
    with pytest.raises(ValueError, match="dtype"):
        Parameter("x", set_value="untested")
    p = Parameter("x", set_value="none", config_key="x")
    assert not p.bmi and not p.safe_to_set


def test_roundtrip(tmp_path):
    cat = load_catalog("cfe")
    cat.write(tmp_path / "c.json")
    assert Catalog.read(tmp_path / "c.json").to_dict() == cat.to_dict()
    assert (tmp_path / "c.json").read_text() == (CATALOG_DIR / "cfe.json").read_text()


def test_unknown_names():
    with pytest.raises(KeyError, match="no parameter"):
        load_catalog("cfe")["nope"]
    with pytest.raises(KeyError, match="no parameter catalog"):
        load_catalog("sft")
    with pytest.raises(KeyError, match="unknown model"):
        load_catalog("nope")


@pytest.mark.parametrize("key", CATALOGED)
def test_packaged_catalog_is_valid(key):
    raw = json.loads((CATALOG_DIR / MODELS[key].catalog).read_text())
    assert raw["model"] == key
    assert raw["codec"] == MODELS[key].codec
    cat = load_catalog(key)
    assert cat.parameters
    for p in cat:
        assert p.set_value in STATUSES
        assert isinstance(p.length, (int, str)) or p.length is None
    keys = [p.config_key for p in cat if p.config_key]
    assert len(keys) == len(set(keys)), "a config key maps to two parameters"


def test_topmodel_config_keys_are_params_dat_columns():
    for p in load_catalog("topmodel"):
        assert p.config_key in TopmodelConfig.PARAMS


def test_noah_sources_name_a_table_column():
    for p in load_catalog("noah"):
        if p.source:
            table, column = p.source.split(":")
            assert table.endswith(".TBL") and column


def test_pet_has_no_bmi_parameters():
    assert load_catalog("pet").bmi_parameters() == []


def test_known_statuses():
    """The results the catalogs record (integration tests re-verify them live)."""
    cfe = load_catalog("cfe")
    assert cfe["max_gw_storage"].set_value == "differs"
    for name in ("b", "satdk", "maxsmc", "Cgw", "refkdt"):
        assert cfe[name].safe_to_set
    noah = load_catalog("noah")
    assert noah["SMCMAX"].safe_to_set and noah["SMCMAX"].length == "nsoil"
    tm = load_catalog("topmodel")
    assert {p.name for p in tm if p.safe_to_set} == {"t0", "szm", "td", "srmax", "sr0", "chv", "rv"}
    assert tm["xk0"].set_value == "unexercised"
