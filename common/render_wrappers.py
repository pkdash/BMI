#!/usr/bin/env python3
"""Render every model's Cython BMI wrapper from the shared templates.

Run from anywhere (Python >= 3.11, or 3.8+ with ``tomli`` installed)::

    python common/render_wrappers.py           # (re)write all generated files
    python common/render_wrappers.py --check   # exit 1 if any are out of date
    python common/render_wrappers.py CFE SFT   # only these models

For each model directory listed in ``MODELS`` this reads ``<dir>/babel.toml``
(the same file Babelizer uses) for the class name, language, header, entry
point and package name, renders ``common/templates/<family>.pyx.in``, and
writes three files into two places:

* ``<dir>/wrapper/``: the vendored copy that ``<dir>/post_babelize_patch.sh``
  installs after ``babelize init``.  It lives inside the model directory
  because the Docker workflow mounts only that directory.
* ``<dir>/<package>/<package>/lib/``: the committed package sources.

Files written: ``<module>.pyx``, ``_bmi_arrays.py`` (copy of
``common/bmi_arrays.py``) and ``bmi_ptr.pxi`` (copy of ``common/bmi_ptr.pxi``),
plus ``<dir>/wrapper/install.sh`` (copy of ``common/install_wrapper.sh``),
which ``post_babelize_patch.sh`` runs.
"""

import argparse
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11
    import tomli as tomllib


COMMON_DIR = Path(__file__).resolve().parent
REPO_ROOT = COMMON_DIR.parent
TEMPLATE_DIR = COMMON_DIR / "templates"

# Model directory -> per-model options that babel.toml cannot express
# (C++ family only):
#   encoding:      Cython c_string_encoding (default "ascii")
#   namespace:     C++ namespace of the BMI class
#   extra_decls:   additional cppclass method declarations (model-specific
#                  public methods beyond the BMI standard)
#   extra_methods: Python methods exposing them, as Cython source indented
#                  for the class body
MODELS = {
    "CFE": {},
    "PET": {},
    "TOPMODEL": {},
    "SOIL-FREEZE-THAW": {},
    "SOIL-MOISTURE-PROFILES": {
        "extra_decls": ["void ResetSize(string name) except +"],
        "extra_methods": """
    def reset_size(self, name):
        self._bmi.ResetSize(name)
""",
    },
    "LASAM": {"encoding": "utf8"},
    "UEB": {
        "encoding": "utf8",
        "namespace": "ueb",
        "extra_decls": [
            "void GetStartTimeInGregorianCalendar(int& y, int& m, int& d, int& h) except +",
            "void GetEndTimeInGregorianCalendar(int& y, int& m, int& d, int& h) except +",
            "void GetCurrentTimeInGregorianCalendar(int& y, int& m, int& d, int& h) except +",
        ],
        "extra_methods": """
    def get_start_time_gregorian(self):
        cdef int y = 0, m = 0, d = 0, h = 0
        self._bmi.GetStartTimeInGregorianCalendar(y, m, d, h)
        return y, m, d, h

    def get_end_time_gregorian(self):
        cdef int y = 0, m = 0, d = 0, h = 0
        self._bmi.GetEndTimeInGregorianCalendar(y, m, d, h)
        return y, m, d, h

    def get_current_time_gregorian(self):
        cdef int y = 0, m = 0, d = 0, h = 0
        self._bmi.GetCurrentTimeInGregorianCalendar(y, m, d, h)
        return y, m, d, h
""",
    },
    "NOAH_OWP": {},
    "SAC_SMA": {},
    "SNOW17": {},
}

FAMILY_BY_LANGUAGE = {"c": "c", "c++": "cxx", "fortran": "fortran"}


def read_babel_config(model_dir):
    path = model_dir / "babel.toml"
    with path.open("rb") as fp:
        config = tomllib.load(fp)
    libraries = config.get("library", {})
    if len(libraries) != 1:
        raise SystemExit(f"{path}: expected exactly one [library.<NAME>] table")
    (class_name, library), = libraries.items()
    return {
        "class_name": class_name,
        "language": library["language"].lower(),
        "header": library.get("header", ""),
        "entry_point": library.get("entry_point", ""),
        "package": config["package"]["name"],
    }


def render_pyx(info, options):
    family = FAMILY_BY_LANGUAGE.get(info["language"])
    if family is None:
        raise SystemExit(f"unsupported Babelizer language {info['language']!r}")
    text = (TEMPLATE_DIR / f"{family}.pyx.in").read_text()

    module = info["class_name"].lower()
    replacements = {
        "@CLASS@": info["class_name"],
        "@MODULE@": module,
        "@HEADER@": info["header"],
        "@ENTRY_POINT@": info["entry_point"],
    }
    if family == "cxx":
        namespace = options.get("namespace")
        extra_decls = "".join(f"        {decl}\n" for decl in options.get("extra_decls", []))
        extra_methods = options.get("extra_methods", "")
        replacements.update({
            "@CXX_CLASS@": info["entry_point"],
            "@NAMESPACE_CLAUSE@": f' namespace "{namespace}"' if namespace else "",
            "@ENCODING@": options.get("encoding", "ascii"),
            "@EXTRA_DECLS@": extra_decls,
            "@EXTRA_METHODS@": extra_methods.rstrip("\n"),
        })
    elif options:
        raise SystemExit(f"options {sorted(options)} only apply to C++ models")

    for token, value in replacements.items():
        text = text.replace(token, value)
    leftover = [tok for tok in ("@CLASS@", "@MODULE@", "@HEADER@", "@ENTRY_POINT@",
                                "@CXX_CLASS@", "@NAMESPACE_CLAUSE@", "@ENCODING@",
                                "@EXTRA_DECLS@", "@EXTRA_METHODS@") if tok in text]
    if leftover:
        raise SystemExit(f"unrendered template tokens: {leftover}")
    # Collapse the blank lines left behind by empty optional sections.
    while "\n\n\n\n" in text:
        text = text.replace("\n\n\n\n", "\n\n\n")
    return module, text.rstrip("\n") + "\n"


def outputs_for(model_dir_name):
    model_dir = REPO_ROOT / model_dir_name
    info = read_babel_config(model_dir)
    module, pyx = render_pyx(info, MODELS[model_dir_name])
    contents = {f"{module}.pyx": pyx}
    contents["_bmi_arrays.py"] = (COMMON_DIR / "bmi_arrays.py").read_text()
    contents["bmi_ptr.pxi"] = (COMMON_DIR / "bmi_ptr.pxi").read_text()

    package = info["package"]
    targets = [
        model_dir / "wrapper",
        model_dir / package / package / "lib",
    ]
    for target in targets:
        for name, text in contents.items():
            yield target / name, text
    # The installer is only needed next to the vendored sources.
    yield model_dir / "wrapper" / "install.sh", (COMMON_DIR / "install_wrapper.sh").read_text()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("models", nargs="*", help="model directories (default: all)")
    parser.add_argument("--check", action="store_true",
                        help="report out-of-date files instead of writing them")
    args = parser.parse_args(argv)

    unknown = sorted(set(args.models) - set(MODELS))
    if unknown:
        parser.error(f"unknown model directories: {unknown}; known: {sorted(MODELS)}")

    stale = []
    for model_dir_name in args.models or MODELS:
        for path, text in outputs_for(model_dir_name):
            if not path.parent.is_dir() and path.parent.name == "lib":
                # Package not generated yet (babelize init not run): the
                # vendored copy in <dir>/wrapper is enough.
                continue
            current = path.read_text() if path.exists() else None
            if current == text:
                continue
            rel = path.relative_to(REPO_ROOT)
            if args.check:
                stale.append(rel)
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("w", newline="\n") as fp:
                fp.write(text)
            print(f"wrote {rel}")

    if stale:
        print("Out of date (run python common/render_wrappers.py):", file=sys.stderr)
        for rel in stale:
            print(f"  {rel}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
