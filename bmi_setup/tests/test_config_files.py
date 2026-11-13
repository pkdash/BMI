"""Config codecs: untouched bytes stay identical; edits change only the value."""

from pathlib import Path

import numpy as np
import pytest

from bmi_setup.config_files import (KeyValueConfig, NamelistConfig, TopmodelConfig,
                                    format_number, open_config)

CFE = """forcing_file=BMI
surface_partitioning_scheme=Schaake
soil_params.depth=2.0[m]
soil_params.satdk=4.698e-06[m s-1]
soil_params.b=6.0[]
refkdt=1.0992179
giuh_ordinates=0.63,0.37
# a comment line
"""

NOAH = """&timing                                             ! and input/output paths
  dt                 = 3600.0                       ! timestep [seconds]
  startdate          = "200710010000"               ! UTC time start (YYYYMMDDhhmm)
/

&parameters
  parameter_dir      = "./data/parameters//"        ! location of input parameter files
/

&structure
 isltyp           = 3               ! soil texture class
 nsoil            = 4               ! number of soil levels
/

&initial_values
 sh2o      =  0.3,  0.3,  0.3,  0.3                       ! initial soil liquid profile [m3/m3]
 zwt       =  -2.0                                        ! initial water table depth below surface [m]
/
"""

TOPMOD_RUN = """1
Taegu Pyungkwang River Catchment: Calibration Data
data/inputs.dat
data/subcat.dat
data/params.dat
topmod.out
hyd.out
"""
PARAMS = "Extracted study basin: Taegu Pyungkwang River\n" \
         "0.032  5.0  50.  3600.0  3600.0  0.05  0.0000328  0.002  0  1.0  0.02  0.1\n"


# ----------------------------------------------------------------- format_number
@pytest.mark.parametrize("value, text", [(2.0e-5, "2e-05"), (0.1, "0.1"), (3, "3"),
                                         (np.float32(0.4), repr(float(np.float32(0.4)))),
                                         (np.int64(7), "7")])
def test_format_number(value, text):
    assert format_number(value) == text
    assert float(text) == float(value)


@pytest.mark.parametrize("bad", [float("nan"), float("inf"), True, "1.0", None])
def test_format_number_rejects(bad):
    with pytest.raises((TypeError, ValueError)):
        format_number(bad)


# ----------------------------------------------------------------- KeyValueConfig
def test_keyvalue_roundtrip_is_byte_identical():
    assert KeyValueConfig(CFE).to_text() == CFE


def test_keyvalue_crlf_roundtrip_and_edit():
    text = CFE.replace("\n", "\r\n")
    cfg = KeyValueConfig(text)
    assert cfg.to_text() == text
    cfg.set("refkdt", 3.0)
    assert "refkdt=3.0\r\n" in cfg.to_text()
    cfg.set("new_key", 1, create=True)
    assert cfg.to_text().endswith("new_key=1\r\n")


def test_keyvalue_get_strips_unit_and_set_keeps_it():
    cfg = KeyValueConfig(CFE)
    assert cfg.get("soil_params.satdk") == "4.698e-06"
    assert cfg.unit("soil_params.satdk") == "m s-1"
    assert cfg.unit("soil_params.b") == ""
    assert cfg.unit("refkdt") is None
    cfg.set("soil_params.satdk", 2.0e-5)
    cfg.set("soil_params.b", 8)
    out = cfg.to_text()
    assert "soil_params.satdk=2e-05[m s-1]\n" in out
    assert "soil_params.b=8[]\n" in out
    changed = [a for a, b in zip(CFE.splitlines(), out.splitlines()) if a != b]
    assert changed == ["soil_params.satdk=4.698e-06[m s-1]", "soil_params.b=6.0[]"]


def test_keyvalue_lists_and_strings():
    cfg = KeyValueConfig(CFE)
    assert cfg.get("giuh_ordinates") == "0.63,0.37"
    cfg.set("giuh_ordinates", [0.5, 0.3, 0.2])
    cfg.set("surface_partitioning_scheme", "Xinanjiang")
    assert "giuh_ordinates=0.5,0.3,0.2\n" in cfg.to_text()
    assert "surface_partitioning_scheme=Xinanjiang\n" in cfg.to_text()


def test_keyvalue_missing_key():
    cfg = KeyValueConfig(CFE)
    with pytest.raises(KeyError):
        cfg.get("nope")
    with pytest.raises(KeyError, match="create=True"):
        cfg.set("nope", 1)
    cfg.set("nope", 1, create=True)
    assert cfg.to_text() == CFE + "nope=1\n"
    assert "nope" in cfg and cfg.keys()[-1] == "nope"


def test_keyvalue_append_to_file_without_final_newline():
    cfg = KeyValueConfig("a=1")
    cfg.set("b", 2, create=True)
    assert cfg.to_text() == "a=1\nb=2\n"


def test_keyvalue_rejects_line_breaks():
    with pytest.raises(ValueError):
        KeyValueConfig(CFE).set("refkdt", "1\nverbosity=3")


def test_keyvalue_file_roundtrip(tmp_path):
    src = tmp_path / "cfe.txt"
    src.write_bytes(CFE.encode())
    cfg = KeyValueConfig.read(src)
    cfg.set("refkdt", 2.5)
    dest = cfg.write(tmp_path / "out.txt")
    assert dest.read_text() == CFE.replace("refkdt=1.0992179", "refkdt=2.5")
    assert src.read_text() == CFE


# ----------------------------------------------------------------- NamelistConfig
def test_namelist_roundtrip_is_byte_identical():
    assert NamelistConfig(NOAH).to_text() == NOAH


def test_namelist_get():
    nml = NamelistConfig(NOAH)
    assert nml.get("isltyp") == "3"
    assert nml.get("structure.ISLTYP") == "3"
    assert nml.get("parameter_dir") == '"./data/parameters//"'
    assert nml.get("sh2o") == "0.3,  0.3,  0.3,  0.3"
    assert "timing.dt" in nml.keys() and "initial_values.zwt" in nml.keys()


def test_namelist_set_keeps_comment_column():
    nml = NamelistConfig(NOAH)
    nml.set("isltyp", 7)
    nml.set("dt", 1800.0)
    nml.set("parameter_dir", "/abs/tables/")
    out = nml.to_text().splitlines()
    before = NOAH.splitlines()
    assert ' isltyp           = 7               ! soil texture class' in out
    assert '  dt                 = 1800.0                       ! timestep [seconds]' in out
    assert '  parameter_dir      = "/abs/tables/"' in nml.to_text()
    assert sum(a != b for a, b in zip(out, before)) == 3


def test_namelist_long_value_and_lists():
    nml = NamelistConfig(NOAH)
    nml.set("sh2o", [0.25, 0.25, 0.25, 0.4])
    nml.set("parameter_dir", "/a/very/long/path/that/is/longer/than/the/old/one/")
    out = nml.to_text()
    assert " sh2o      =  0.25, 0.25, 0.25, 0.4" in out
    assert '"/a/very/long/path/that/is/longer/than/the/old/one/" ! location' in out


def test_namelist_comment_inside_quotes_is_not_a_comment():
    nml = NamelistConfig('&a\n  name = "x!y"   ! real comment\n/\n')
    assert nml.get("name") == '"x!y"'
    nml.set("name", "z")
    assert nml.to_text() == '&a\n  name = "z"     ! real comment\n/\n'


def test_namelist_ambiguous_and_missing_keys():
    nml = NamelistConfig("&a\n x = 1\n/\n&b\n x = 2\n/\n")
    with pytest.raises(KeyError, match="several groups"):
        nml.get("x")
    assert nml.get("b.x") == "2"
    with pytest.raises(KeyError):
        nml.get("y")
    with pytest.raises(KeyError):
        nml.set("c.x", 1)


def test_namelist_ignores_lines_outside_groups():
    nml = NamelistConfig("x = 1\n&a\n y = 2\n/\nz = 3\n")
    assert nml.keys() == ["a.y"]


# ----------------------------------------------------------------- TopmodelConfig
@pytest.fixture
def topmodel_dir(tmp_path):
    (tmp_path / "data").mkdir()
    (tmp_path / "topmod.run").write_text(TOPMOD_RUN)
    (tmp_path / "data" / "params.dat").write_text(PARAMS)
    return tmp_path


def test_topmodel_read(topmodel_dir):
    cfg = TopmodelConfig.read(topmodel_dir / "topmod.run", topmodel_dir)
    assert cfg.stand_alone is True
    assert cfg.params_file == "data/params.dat"
    assert cfg.inputs_file == "data/inputs.dat"
    assert cfg.get("szm") == "0.032"
    assert cfg.get("Q0") == "0.0000328"
    assert cfg.get("dth") == "0.1"
    assert cfg.run_text() == TOPMOD_RUN and cfg.params_text() == PARAMS


def test_topmodel_set_keeps_columns(topmodel_dir):
    cfg = TopmodelConfig.read(topmodel_dir / "topmod.run", topmodel_dir)
    cfg.set("td", 75.0)
    cfg.set("szm", 0.048)
    cfg.set("infex", 1)
    line = cfg.params_text().splitlines()[1]
    assert line.split() == ["0.048", "5.0", "75.0", "3600.0", "3600.0", "0.05", "0.0000328",
                            "0.002", "1", "1.0", "0.02", "0.1"]
    assert cfg.params_text().splitlines()[0] == PARAMS.splitlines()[0]
    # Same-width edits leave the spacing alone.
    cfg2 = TopmodelConfig(TOPMOD_RUN, PARAMS)
    cfg2.set("t0", 6.0)
    assert cfg2.params_text() == PARAMS.replace("  5.0  ", "  6.0  ")


def test_topmodel_unknown_column_and_bad_value():
    cfg = TopmodelConfig(TOPMOD_RUN, PARAMS)
    with pytest.raises(KeyError):
        cfg.get("nope")
    with pytest.raises(ValueError):
        cfg.set("szm", "1 2")


def test_topmodel_requires_full_files():
    with pytest.raises(ValueError):
        TopmodelConfig("1\ntitle\n", PARAMS)
    with pytest.raises(ValueError, match="12"):
        TopmodelConfig(TOPMOD_RUN, "title\n0.032 5.0\n")


def test_topmodel_write_in_place(topmodel_dir):
    cfg = TopmodelConfig.read(topmodel_dir / "topmod.run", topmodel_dir)
    cfg.set("szm", 0.04)
    cfg.write()
    assert (topmodel_dir / "data" / "params.dat").read_text().split()[6] == "0.04"
    assert (topmodel_dir / "topmod.run").read_text() == TOPMOD_RUN


def test_topmodel_write_elsewhere_repoints_run(topmodel_dir, tmp_path):
    cfg = TopmodelConfig.read(topmodel_dir / "topmod.run", topmodel_dir)
    cfg.set("t0", 7.5)
    cfg.stand_alone = False
    out = topmodel_dir / "case1"
    out.mkdir()
    cfg.write(out / "run.run", params_path=out / "params.dat")
    run = (out / "run.run").read_text().splitlines()
    assert run[0] == "0" and run[4] == "case1/params.dat"
    assert (topmodel_dir / "case1" / "params.dat").read_text().splitlines()[1].split()[1] == "7.5"
    # A params file outside the working directory is referenced absolutely.
    other = tmp_path.parent / (tmp_path.name + "_other")
    other.mkdir()
    cfg.write(out / "run2.run", params_path=other / "p.dat")
    assert Path((out / "run2.run").read_text().splitlines()[4]).is_absolute()
    with pytest.raises(ValueError):
        cfg.set_path("params_file", "has space/p.dat")


def test_open_config_dispatch(topmodel_dir, tmp_path):
    (tmp_path / "c.txt").write_text(CFE)
    assert isinstance(open_config("KeyValueConfig", tmp_path / "c.txt"), KeyValueConfig)
    tm = open_config("TopmodelConfig", topmodel_dir / "topmod.run", topmodel_dir)
    assert tm.get("szm") == "0.032"
