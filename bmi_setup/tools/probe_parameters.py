#!/usr/bin/env python
"""Draft a parameter catalog for a model by probing its compiled library.

Development tool: run it when a model's library changes, review the draft, and
commit it as ``bmi_setup/catalogs/<model>.json``. Users never run it.

    python tools/probe_parameters.py cfe --config cat-11223_bmi_config_cfe_pass.txt \\
        --source /path/to/cfe/src/bmi_cfe.c [--merge] [--out draft.json]

What it does:

1. Initializes the model from ``--config`` (in ``--workdir``, default the
   config's directory), without the catalog check.
2. Harvests identifier-like string literals from the model's BMI source
   (``--source``) and keeps those the library accepts as variables but does not
   list among its inputs or outputs. Nothing from the source is trusted: every
   name is confirmed live.
3. For each, records dtype, length and units from the library, and checks that
   ``set`` of its current value reads back unchanged.
4. Matches each to a config key by value (element 0 against every numeric
   config value). A single exact match becomes ``config_key``; anything else is
   left ``null`` with the candidates in ``note`` for the reviewer.
5. Lists numeric config keys that matched nothing under
   ``_config_only_candidates``; the reviewer moves the real parameters into
   ``parameters`` with ``"set_value": "none"``.

BMI entries are drafted as ``"set_value": "untested"``. Run
``tools/check_equivalence.py`` to classify them. With ``--merge`` the packaged
catalog's reviewed fields (``config_key``, ``set_value``, ``source``, and a
config-dependent ``length``) are kept, old and new notes are both kept, and
differences in dtype/length/units are reported on stderr. A numeric ``length``
and the dtype and units are taken from the library.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np

from bmi_setup import Model, get_spec, load_catalog, open_config
from bmi_setup.catalog import STATUSES

_NUMBER = re.compile(r"\s*([-+]?(\d+\.?\d*|\.\d+)([eEdD][-+]?\d+)?)\s*$")


def harvest_names(source: Path):
    text = source.read_text(errors="replace")
    return sorted(set(re.findall(r"""['"]([A-Za-z_][A-Za-z0-9_]*)['"]""", text)))


def numeric_config_values(key: str, config: Path, workdir: Path):
    """``{config key: float}`` for every single-number value in the config."""
    spec = get_spec(key)
    if not spec.codec:
        return {}
    cfg = open_config(spec.codec, config, workdir)
    out = {}
    for k in cfg.keys():
        m = _NUMBER.match(cfg.get(k).replace("d", "e").replace("D", "E"))
        if m:
            out[k] = float(m.group(1))
    return out


def probe(key: str, config: Path, workdir: Path, source: Path):
    cfg_values = numeric_config_values(key, config, workdir)
    used_keys = set()
    params = {}
    m = Model(key, catalog=False)
    m.initialize(config, workdir, check_catalog=False)
    try:
        advertised = set(m.input_names) | set(m.output_names)
        for name in harvest_names(source):
            if name in advertised or not m.is_var(name):
                continue
            entry = {"dtype": str(m.var_dtype(name)), "length": m.var_length(name)}
            try:
                entry["units"] = m.var_units(name)
            except Exception:                           # noqa: BLE001
                pass
            notes = []
            try:
                value = m.get(name)
                m.set(name, value)
                if not np.array_equal(m.get(name), value, equal_nan=True):
                    notes.append("set_value of the current value did not read back unchanged")
            except Exception as err:                    # noqa: BLE001
                notes.append(f"get/set failed: {err}")
                value = None
            matches = []
            if value is not None and value.size and np.isfinite(value[0]) and value[0] != 0:
                v = float(value[0])
                matches = [k for k, c in cfg_values.items()
                           if abs(c - v) <= 1e-6 * abs(v)]
            if name in matches:                         # same name as a config key wins
                matches = [name]
            if len(matches) == 1:
                entry["config_key"] = matches[0]
                used_keys.add(matches[0])
            else:
                entry["config_key"] = None
                if matches:
                    notes.append(f"several config keys match by value: {matches}")
            entry["set_value"] = "untested"
            if notes:
                entry["note"] = "; ".join(notes)
            params[name] = entry
    finally:
        m.finalize()
    leftovers = {k: v for k, v in cfg_values.items() if k not in used_keys}
    return params, leftovers


def merge(key: str, drafted: dict):
    """Keep reviewed fields from the packaged catalog; report library drift."""
    try:
        current = load_catalog(key).to_dict()["parameters"]
    except (KeyError, FileNotFoundError):
        return drafted
    merged = {}
    for name, entry in current.items():
        if entry.get("set_value") == "none":
            merged[name] = entry                       # config-only: nothing to probe
            continue
        new = drafted.get(name)
        if new is None:
            print(f"! {name}: in the catalog but no longer found in the library", file=sys.stderr)
            merged[name] = entry
            continue
        for field in ("dtype", "length", "units"):
            if field in entry and entry[field] != new.get(field) and not (
                    field == "length" and isinstance(entry[field], str)):
                print(f"! {name}: {field} changed {entry[field]!r} -> {new.get(field)!r}",
                      file=sys.stderr)
        # A numeric length comes from the library, so the probe's wins; a
        # config-dependent length (a key name such as "nsoil") is reviewed.
        kept = ("config_key", "set_value", "source")
        if isinstance(entry.get("length"), str):
            kept += ("length",)
        merged[name] = {**new, **{k: entry[k] for k in kept if k in entry}}
        notes = [n for n in (entry.get("note"), new.get("note")) if n]
        if notes:
            merged[name]["note"] = "; ".join(dict.fromkeys(notes))
    for name, new in drafted.items():
        if name not in merged:
            print(f"+ {name}: new in the library", file=sys.stderr)
            merged[name] = new
    return merged


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("model", help="model key, e.g. cfe")
    ap.add_argument("--config", required=True, type=Path)
    ap.add_argument("--workdir", type=Path, help="directory to initialize in (default: the config's)")
    ap.add_argument("--source", required=True, type=Path, help="the model's BMI implementation source")
    ap.add_argument("--merge", action="store_true", help="keep reviewed fields from the packaged catalog")
    ap.add_argument("--out", type=Path, help="write the draft here (default: stdout)")
    args = ap.parse_args(argv)

    config = args.config.resolve()                      # relative to the current directory
    workdir = (args.workdir or config.parent).resolve()
    params, leftovers = probe(args.model, config, workdir, args.source)
    if args.merge:
        params = merge(args.model, params)
    draft = {"model": args.model,
             "_draft": f"generated by tools/probe_parameters.py; review before committing. "
                       f"set_value is one of {list(STATUSES)}.",
             "parameters": params,
             "_config_only_candidates": leftovers}
    text = json.dumps(draft, indent=2) + "\n"
    if args.out:
        args.out.write_text(text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
