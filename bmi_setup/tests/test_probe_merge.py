"""tools/probe_parameters.py --merge: which fields come from the library, which from review."""

import importlib.util
from pathlib import Path

from bmi_setup import Catalog

_spec = importlib.util.spec_from_file_location(
    "probe_parameters", Path(__file__).resolve().parents[1] / "tools" / "probe_parameters.py")
probe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(probe)


def test_merge_takes_library_length_and_keeps_both_notes(monkeypatch, capsys):
    reviewed = Catalog.from_dict({"model": "fake", "parameters": {
        "k": {"dtype": "float64", "length": 1, "config_key": "k_cfg", "set_value": "equivalent",
              "note": "reviewed by hand"},
        "layers": {"dtype": "float64", "length": "nsoil", "set_value": "untested"},
    }})
    monkeypatch.setattr(probe, "load_catalog", lambda key: reviewed)
    drafted = {
        "k": {"dtype": "float64", "length": 3, "config_key": None, "set_value": "untested",
              "note": "set_value of the current value did not read back unchanged"},
        "layers": {"dtype": "float64", "length": 4, "config_key": None, "set_value": "untested"},
    }
    merged = probe.merge("fake", drafted)
    assert merged["k"]["length"] == 3                       # from the library
    assert merged["k"]["config_key"] == "k_cfg" and merged["k"]["set_value"] == "equivalent"
    assert merged["k"]["note"] == ("reviewed by hand; "
                                   "set_value of the current value did not read back unchanged")
    assert merged["layers"]["length"] == "nsoil"            # config-dependent: reviewed
    assert "length changed 1 -> 3" in capsys.readouterr().err
