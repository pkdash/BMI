#!/usr/bin/env python
"""Classify every catalog parameter: is setting it through BMI the same as a config edit?

Development tool, run where the wrappers and native libraries are installed.
Configure it with the environment variables described in
``tests/integration/cases.py`` (``PYMT_<KEY>_CONFIG``, ``BMI_SETUP_FORCING_CSV``).

    python tools/check_equivalence.py [cfe noah topmodel] [--update] [--json out.json]

For each parameter with both a BMI variable and a config route, it runs the
three-way comparison in :mod:`bmi_setup.verify` and prints the result next to
the catalog's current status. ``--update`` writes the new statuses into the
packaged catalogs (review the diff before committing). The integration test
``tests/integration/test_wrappers.py::test_equivalence`` asserts the catalog
statuses with the same cases.
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "tests" / "integration"))

from cases import cases_for, make_setup  # noqa: E402

from bmi_setup.catalog import CATALOG_DIR  # noqa: E402
from bmi_setup.models import get_spec  # noqa: E402


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("models", nargs="*", default=["cfe", "noah", "topmodel"])
    ap.add_argument("--update", action="store_true", help="write statuses into the catalogs")
    ap.add_argument("--json", type=Path, help="also write the full results here")
    args = ap.parse_args(argv)

    results = []
    with tempfile.TemporaryDirectory(prefix="bmi_setup_equiv_") as tmp:
        for key in args.models:
            setup = make_setup(key, Path(tmp))
            if setup is None:
                print(f"{key}: not configured (see tests/integration/cases.py)", file=sys.stderr)
                continue
            changed = False
            for case in cases_for(setup):
                r = setup.run(case)
                old = setup.catalog[case.param].set_value
                flag = "" if old == r.status else f"   (catalog: {old})"
                print(f"{key:<9} {case.param:<42} {r.status:<12} effect={r.effect:<10.3g} "
                      f"config-vs-bmi={r.difference:<10.3g} {r.difference_output or ''}{flag}")
                results.append({"model": key, "new_value": case.new_value,
                                "base_edits": case.base_edits, **r.as_dict()})
                if old != r.status:
                    setup.catalog.parameters[case.param].set_value = r.status
                    changed = True
            if args.update and changed:
                setup.catalog.write(CATALOG_DIR / get_spec(key).catalog)
                print(f"{key}: catalog updated", file=sys.stderr)
    if args.json:
        args.json.write_text(json.dumps(results, indent=1))


if __name__ == "__main__":
    main()
