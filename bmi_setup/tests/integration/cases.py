"""Model setups for the equivalence tests and ``tools/check_equivalence.py``.

Locations come from the same environment variables as
``common/tests/test_native_models.py``:

    PYMT_CFE_CONFIG, PYMT_NOAH_OWP_CONFIG, PYMT_PET_CONFIG, PYMT_TOPMODEL_CONFIG
    PYMT_<KEY>_WORKDIR      optional; directory the config's relative paths are
                            resolved from (default: the config's directory)
    BMI_SETUP_FORCING_CSV   hourly forcing CSV with AORC column names, as ngen
                            uses (APCP_surface in mm per hour, DLWRF_surface, ...).
                            Needed for CFE and Noah.

Each setup copies what it needs into a scratch directory, so the originals are
never modified.
"""

from __future__ import annotations

import csv
import os
import re
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Optional

import numpy as np

from bmi_setup import KeyValueConfig, NamelistConfig, TopmodelConfig, load_catalog, open_model
from bmi_setup.verify import check_equivalence

ENV_KEY = {"cfe": "CFE", "noah": "NOAH_OWP", "pet": "PET", "topmodel": "TOPMODEL"}
STEPS = 720


def configured(key: str) -> Optional[tuple]:
    """``(config, workdir)`` from the environment, or None when not set."""
    config = os.environ.get(f"PYMT_{ENV_KEY[key]}_CONFIG")
    if not config:
        return None
    # Same resolution as common/tests/test_native_models.py: the config is
    # relative to the current directory, and WORKDIR defaults to its directory.
    config = Path(config).resolve()
    workdir = os.environ.get(f"PYMT_{ENV_KEY[key]}_WORKDIR")
    return config, Path(workdir or config.parent).resolve()


def forcing_csv() -> Optional[Path]:
    path = os.environ.get("BMI_SETUP_FORCING_CSV")
    return Path(path) if path else None


def read_forcing(path: Path, steps: int) -> Dict[str, np.ndarray]:
    with open(path, newline="") as fh:
        rows = list(csv.DictReader(fh))[:steps]
    if len(rows) < steps:
        raise ValueError(f"{path} has {len(rows)} rows, {steps} needed")
    data = {k: np.array([float(r[k]) for r in rows]) for k in rows[0] if k != "time"}
    # APCP_surface is mm accumulated over the hour; the precip_rate column in
    # these files is not on the same scale, so derive the rate from APCP.
    data["precip_mm_s"] = data["APCP_surface"] / 3600.0
    return data


# Conversions from mm s-1 to the units the models report for their inputs.
_FROM_MM_S = {"mm s-1": 1.0, "mm/s": 1.0, "kg m-2 s-1": 1.0, "mm h-1": 3600.0, "mm/h": 3600.0,
              "m s-1": 1e-3, "m/s": 1e-3, "m h-1": 3.6, "m": 3.6}


def mm_s_to(units: str, values):
    try:
        return np.asarray(values) * _FROM_MM_S[units.strip()]
    except KeyError:
        raise ValueError(f"no conversion from mm s-1 to {units!r}") from None


@dataclass
class Case:
    """Compare a config edit of ``param`` with setting it through BMI."""
    model: str
    param: str
    new_value: float
    base_edits: Dict = field(default_factory=dict)    # make the parameter matter

    @property
    def id(self) -> str:
        return f"{self.model}-{self.param}"


class Setup:
    key: str

    def __init__(self, config: Path, workdir: Path, scratch: Path):
        self.config, self.workdir, self.scratch = config, workdir, scratch
        self.scratch.mkdir(parents=True, exist_ok=True)
        self.catalog = load_catalog(self.key)
        self._n = 0

    def edit_key(self, param: str) -> str:
        p = self.catalog[param]
        return p.config_key or p.source

    def write_config(self, edits: Dict) -> Path:            # pragma: no cover - abstract
        raise NotImplementedError

    def open(self, config: Path):
        return open_model(self.key, config, self.scratch)

    def forcing(self) -> Optional[Dict[str, np.ndarray]]:
        return None

    def current(self, key: str, base_edits: Dict) -> float:  # pragma: no cover - abstract
        raise NotImplementedError

    def run(self, case: Case, steps: int = STEPS):
        key = self.edit_key(case.param)
        base = self.write_config(case.base_edits)
        edited = self.write_config({**case.base_edits, key: case.new_value})
        return check_equivalence(lambda: self.open(base), lambda: self.open(edited),
                                 case.param, steps, self.forcing())

    def _next(self, stem: str) -> Path:
        self._n += 1
        return self.scratch / f"{stem}_{self._n}"


class CfeSetup(Setup):
    key = "cfe"
    INPUTS = ("atmosphere_water__liquid_equivalent_precipitation_rate",
              "water_potential_evaporation_flux")

    def __init__(self, config, workdir, scratch, forcing_path: Path):
        super().__init__(config, workdir, scratch)
        self._forcing_path = forcing_path
        self._forcing = None

    def write_config(self, edits):
        cfg = KeyValueConfig.read(self.config)
        for k, v in edits.items():
            cfg.set(k, v, create=True)
        return cfg.write(self._next("cfe").with_suffix(".txt"))

    def current(self, key, base_edits):
        if key in base_edits:
            return float(base_edits[key])
        return float(re.match(r"\s*([^\s,]+)", KeyValueConfig.read(self.config).get(key)).group(1))

    def forcing(self):
        if self._forcing is None:
            f = read_forcing(self._forcing_path, STEPS)
            with self.open(self.write_config({})) as m:
                precip_units = m.var_units(self.INPUTS[0])
                pet_units = m.var_units(self.INPUTS[1])
            self._forcing = {
                self.INPUTS[0]: mm_s_to(precip_units, f["precip_mm_s"]),
                # Constant 5e-6 mm s-1 (about 0.4 mm/day) potential ET.
                self.INPUTS[1]: np.full(STEPS, mm_s_to(pet_units, 5.0e-6)),
            }
        return self._forcing


class NoahSetup(Setup):
    """Noah-OWP: the BMI parameters come from the parameter tables.

    The namelist's ``parameter_dir`` is pointed at a scratch copy of the tables,
    edited in place. Table editing is test-only code: it is out of scope for the
    package (see the Noah catalog note).
    """
    key = "noah"
    FORCING = {"SFCPRS": "PRES_surface", "SFCTMP": "TMP_2maboveground", "SOLDN": "DSWRF_surface",
               "LWDN": "DLWRF_surface", "UU": "UGRD_10maboveground", "VV": "VGRD_10maboveground",
               "Q2": "SPFH_2maboveground", "PRCPNONC": "precip_mm_s"}

    def __init__(self, config, workdir, scratch, forcing_path: Path):
        super().__init__(config, workdir, scratch)
        self._forcing_path = forcing_path
        nml = NamelistConfig.read(self.config)
        self.tables = (self.workdir / nml.get("parameter_dir").strip("\"'")).resolve()
        self.isltyp = int(nml.get("isltyp"))

    def _soil_row(self, lines):
        header = re.findall(r"[A-Z0-9]+", lines[2].split("'")[1])
        for i, line in enumerate(lines[3:], 3):
            if line.split(",")[0].strip() == str(self.isltyp):
                return i, header
        raise ValueError(f"soil class {self.isltyp} not in SOILPARM.TBL")

    def _edit_table(self, tables: Path, key: str, value) -> None:
        table, column = key.split(":")
        path = tables / table
        lines = path.read_text().splitlines()
        if table == "SOILPARM.TBL":
            i, header = self._soil_row(lines)
            parts = lines[i].split(",")
            parts[header.index(column) + 1] = f"   {value!r}"
            lines[i] = ",".join(parts)
        elif table == "GENPARM.TBL":
            i = next(i for i, line in enumerate(lines) if line.strip() == column)
            lines[i + 1] = repr(value)
        else:
            raise ValueError(f"no editor for {table}")
        path.write_text("\n".join(lines) + "\n")

    def _read_table(self, key: str) -> float:
        table, column = key.split(":")
        lines = (self.tables / table).read_text().splitlines()
        if table == "SOILPARM.TBL":
            i, header = self._soil_row(lines)
            return float(lines[i].split(",")[header.index(column) + 1])
        i = next(i for i, line in enumerate(lines) if line.strip() == column)
        return float(lines[i + 1])

    def write_config(self, edits):
        tables = self._next("noah_tables")
        shutil.copytree(self.tables, tables)
        nml = NamelistConfig.read(self.config)
        for k, v in edits.items():
            if ".TBL:" in k:
                self._edit_table(tables, k, v)
            else:
                nml.set(k, v)
        nml.set("parameter_dir", f"{tables}/")
        return nml.write(tables.with_suffix(".input"))

    def current(self, key, base_edits):
        return float(base_edits[key]) if key in base_edits else self._read_table(key)

    def forcing(self):
        f = read_forcing(self._forcing_path, STEPS)
        return {var: f[col] for var, col in self.FORCING.items()}


class TopmodelSetup(Setup):
    """TOPMODEL in stand-alone mode: it reads its own forcing from inputs.dat."""
    key = "topmodel"

    def write_config(self, edits):
        d = self._next("topmodel")
        d.mkdir()
        cfg = TopmodelConfig.read(self.config, self.workdir)
        for item in ("inputs_file", "subcat_file"):
            src = self.workdir / getattr(cfg, item)
            shutil.copy(src, d / src.name)
            cfg.set_path(item, src.name)
        cfg.set_path("output_file", "topmod.out")
        cfg.set_path("hydrograph_file", "hyd.out")
        cfg.stand_alone = True
        for k, v in edits.items():
            cfg.set(k, v)
        return cfg.write(d / "topmod.run", params_path=d / "params.dat", workdir=d)

    def open(self, config):
        return open_model(self.key, config, config.parent)

    def current(self, key, base_edits):
        if key in base_edits:
            return float(base_edits[key])
        return float(TopmodelConfig.read(self.config, self.workdir).get(key))


# New values: x1.5 of the current one unless listed in OVERRIDES, and the config
# changes that make a parameter matter at all.
CFE_XINANJIANG = {"surface_partitioning_scheme": "Xinanjiang",
                  "a_Xinanjiang_inflection_point_parameter": -0.2,
                  "b_Xinanjiang_shape_parameter": 0.66,
                  "x_Xinanjiang_shape_parameter": 0.02,
                  "urban_decimal_fraction": 0.0}
CFE_NASH_SURFACE = {"surface_runoff_scheme": "NASH_CASCADE", "N_nash_surface": 2,
                    "K_nash_surface": 0.83089, "nsubsteps_nash_surface": 10,
                    "nash_storage_surface": "0.0,0.0", "Kinf_nash_surface": 0.05,
                    "retention_depth_nash_surface": 0.001}
OVERRIDES = {
    "cfe": {"maxsmc": 0.40, "wltsmc": 0.07, "alpha_fc": 0.5, "Klf": 0.05, "Kn": 0.10,
            # x1.5 (-0.3) changes nothing over the test window; -1.0 does.
            "a_Xinanjiang_inflection_point_parameter": -1.0},
    "noah": {"BEXP": 7.0, "DKSAT": 2.0e-05, "SMCMAX": 0.40, "REFKDT": 0.5},
    # Channel velocities need a large change to show in the hydrograph (M1).
    "topmodel": {"chv": 36.0, "rv": 36.0},
}
BASE_EDITS = {
    ("cfe", "a_Xinanjiang_inflection_point_parameter"): CFE_XINANJIANG,
    ("cfe", "b_Xinanjiang_shape_parameter"): CFE_XINANJIANG,
    ("cfe", "x_Xinanjiang_shape_parameter"): CFE_XINANJIANG,
    ("cfe", "Kinf_nash_surface"): CFE_NASH_SURFACE,
    ("cfe", "retention_depth_nash_surface"): CFE_NASH_SURFACE,
    ("topmodel", "xk0"): {"infex": 1},
}


def make_setup(key: str, scratch: Path) -> Optional[Setup]:
    """The setup for ``key``, or None when the environment does not configure it."""
    where = configured(key)
    if where is None:
        return None
    config, workdir = where
    if key == "topmodel":
        return TopmodelSetup(config, workdir, scratch / key)
    forcing = forcing_csv()
    if forcing is None:
        return None
    cls = {"cfe": CfeSetup, "noah": NoahSetup}.get(key)
    return cls(config, workdir, scratch / key, forcing) if cls else None


def cases_for(setup: Setup):
    """One case per catalog entry that has both a BMI variable and a config route."""
    out = []
    for p in setup.catalog.bmi_parameters():
        key = p.config_key or p.source
        if not key:
            continue
        base_edits = BASE_EDITS.get((setup.key, p.name), {})
        new = OVERRIDES.get(setup.key, {}).get(p.name)
        if new is None:
            new = setup.current(key, base_edits) * 1.5
        out.append(Case(setup.key, p.name, new, base_edits))
    return out
