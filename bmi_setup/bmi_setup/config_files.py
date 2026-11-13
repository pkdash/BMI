"""Read, modify and write a model's own init-config file.

Each codec changes only the keys it is asked to change. Every other byte of the
file (comments, ordering, spacing, unit suffixes, untouched lines) is written
back exactly as it was read, so a diff of an edited config shows only the edit.

| Codec             | Models    | Format                                            |
|-------------------|-----------|---------------------------------------------------|
| ``KeyValueConfig``| CFE, PET  | ``key=value`` lines; CFE values may end ``[unit]`` |
| ``TopmodelConfig``| TOPMODEL  | ``.run`` file plus the positional ``params.dat``  |
| ``NamelistConfig``| Noah-OWP  | Fortran namelist ``.input``                        |

All three share the same small interface: ``read``, ``keys``, ``get``, ``set``,
``to_text`` and ``write``. ``get`` returns the value as written in the file
(a string, without any unit suffix); ``set`` accepts numbers, strings, booleans
and sequences and formats them for that file type.
"""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import List, Optional, Tuple, Union

import numpy as np

__all__ = ["KeyValueConfig", "NamelistConfig", "TopmodelConfig", "format_number", "open_config"]

PathLike = Union[str, "os.PathLike[str]"]


def format_number(value) -> str:
    """Shortest text that reads back as exactly ``value``.

    ``repr`` of a Python float round-trips exactly through C ``strtod``/``fscanf``
    and Fortran list-directed reads, so the model sees the same double that was
    passed in. NumPy scalars are converted first so ``np.float32(0.4)`` is not
    written as ``np.float32(0.4)``.
    """
    if isinstance(value, (bool, np.bool_)):
        raise TypeError("booleans have a model-specific spelling; pass a string")
    if isinstance(value, (np.integer, int)):
        return str(int(value))
    if isinstance(value, (np.floating, float)):
        value = float(value)
        if not np.isfinite(value):
            raise ValueError(f"cannot write non-finite value {value!r} to a config file")
        return repr(value)
    raise TypeError(f"not a number: {value!r}")


def _is_sequence(value) -> bool:
    return isinstance(value, (list, tuple, np.ndarray)) and np.ndim(value) == 1


def _read_text(path: PathLike) -> str:
    # newline="" keeps \r\n line endings intact for a byte-for-byte rewrite.
    with open(path, encoding="utf-8", newline="") as fh:
        return fh.read()


def _write_text(path: PathLike, text: str) -> None:
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)


# --------------------------------------------------------------------------
# key=value (CFE, PET)
# --------------------------------------------------------------------------


class KeyValueConfig:
    """``key=value`` config files, one entry per line (CFE, PET).

    A value may carry a trailing unit in brackets (CFE: ``satdk=4.698e-06[m s-1]``).
    ``get`` returns the value without it and ``set`` keeps it, because CFE warns
    when a unit it expects is missing. Lists are comma-separated
    (``giuh_ordinates=0.63,0.37``). Lines without ``=`` are kept as they are.
    """

    _LINE = re.compile(r"^(?P<lead>\s*)(?P<key>[^=\s]+)(?P<eq>\s*=\s*)(?P<value>[^\[\r\n]*?)"
                       r"(?P<unit>\s*\[[^\]\r\n]*\])?(?P<tail>\s*)$")

    def __init__(self, text: str, path: Optional[PathLike] = None):
        self.path = Path(path) if path is not None else None
        self._lines: List[str] = text.splitlines(keepends=True)

    @classmethod
    def read(cls, path: PathLike) -> "KeyValueConfig":
        return cls(_read_text(path), path)

    def _find(self, key: str) -> Optional[Tuple[int, "re.Match[str]"]]:
        found = None
        for i, line in enumerate(self._lines):
            m = self._LINE.match(line.rstrip("\r\n"))
            if m and m.group("key") == key:
                found = (i, m)          # the models keep the last occurrence
        return found

    def keys(self) -> List[str]:
        out = []
        for line in self._lines:
            m = self._LINE.match(line.rstrip("\r\n"))
            if m and m.group("key") not in out:
                out.append(m.group("key"))
        return out

    def __contains__(self, key: str) -> bool:
        return self._find(key) is not None

    def get(self, key: str) -> str:
        hit = self._find(key)
        if hit is None:
            raise KeyError(key)
        return hit[1].group("value").strip()

    def unit(self, key: str) -> Optional[str]:
        """The bracketed unit written after ``key``'s value, without brackets."""
        hit = self._find(key)
        if hit is None:
            raise KeyError(key)
        unit = hit[1].group("unit")
        return unit.strip()[1:-1] if unit else None

    @staticmethod
    def format_value(value) -> str:
        if isinstance(value, str):
            return value
        if _is_sequence(value):
            return ",".join(format_number(v) for v in value)
        return format_number(value)

    def set(self, key: str, value, create: bool = False) -> None:
        """Replace ``key``'s value, keeping its unit suffix and line ending.

        A missing key raises ``KeyError`` unless ``create=True``, in which case a
        ``key=value`` line is appended. Some models read keys in order (CFE reads
        the Xinanjiang parameters only after ``surface_partitioning_scheme``), so
        appending is right for new keys and wrong for reordering existing ones.
        """
        text = self.format_value(value)
        if "\n" in text or "\r" in text:
            raise ValueError(f"value for {key!r} contains a line break")
        hit = self._find(key)
        if hit is None:
            if not create:
                raise KeyError(f"{key!r} is not in this config (pass create=True to add it)")
            if self._lines and not self._lines[-1].endswith(("\n", "\r")):
                self._lines[-1] += self._newline()
            self._lines.append(f"{key}={text}{self._newline()}")
            return
        i, m = hit
        line = self._lines[i]
        ending = line[len(line.rstrip("\r\n")):]
        self._lines[i] = (m.group("lead") + m.group("key") + m.group("eq") + text
                          + (m.group("unit") or "") + m.group("tail") + ending)

    def _newline(self) -> str:
        for line in self._lines:
            if line.endswith("\r\n"):
                return "\r\n"
        return "\n"

    def to_text(self) -> str:
        return "".join(self._lines)

    def write(self, path: Optional[PathLike] = None) -> Path:
        dest = Path(path) if path is not None else self.path
        if dest is None:
            raise ValueError("no path given and the config was not read from a file")
        _write_text(dest, self.to_text())
        return dest


# --------------------------------------------------------------------------
# Fortran namelist (Noah-OWP)
# --------------------------------------------------------------------------


class NamelistConfig:
    """Fortran namelist files (Noah-OWP-Modular's ``.input``).

    Keys may be given bare (``"isltyp"``) when the name occurs in only one
    group, or qualified (``"structure.isltyp"``). Names are case-insensitive,
    as in Fortran. Only ``name = value`` lines that sit inside a group
    (``&group`` ... ``/``) are recognized; a value ends at a ``!`` comment that
    is outside quotes. Strings are written double-quoted, and lists
    comma-separated.

    This codec covers the namelist only. Noah's parameter tables
    (``SOILPARM.TBL`` etc.) are a different format and are out of scope.
    """

    _GROUP = re.compile(r"^\s*&(?P<name>\w+)")
    _END = re.compile(r"^\s*/")
    _ENTRY = re.compile(r"^(?P<lead>\s*)(?P<key>[A-Za-z]\w*)(?P<eq>\s*=\s*)")

    def __init__(self, text: str, path: Optional[PathLike] = None):
        self.path = Path(path) if path is not None else None
        self._lines: List[str] = text.splitlines(keepends=True)

    @classmethod
    def read(cls, path: PathLike) -> "NamelistConfig":
        return cls(_read_text(path), path)

    @staticmethod
    def _split_comment(rest: str) -> Tuple[str, str]:
        """(value incl. trailing spaces, comment) for the text after ``=``."""
        quote = None
        for i, ch in enumerate(rest):
            if quote:
                if ch == quote:
                    quote = None
            elif ch in "\"'":
                quote = ch
            elif ch == "!":
                return rest[:i], rest[i:]
        return rest, ""

    def _entries(self):
        """Yield (line index, group, key, match) for every ``key = value`` line."""
        group = None
        for i, line in enumerate(self._lines):
            body = line.rstrip("\r\n")
            g = self._GROUP.match(body)
            if g:
                group = g.group("name").lower()
                continue
            if group is not None and self._END.match(body):
                group = None
                continue
            if group is None:
                continue
            m = self._ENTRY.match(body)
            if m:
                yield i, group, m.group("key").lower(), m

    def keys(self) -> List[str]:
        return [f"{g}.{k}" for _, g, k, _ in self._entries()]

    def _find(self, key: str):
        key = key.lower()
        group, _, name = key.rpartition(".")
        hits = [(i, g, k, m) for i, g, k, m in self._entries()
                if k == name and (not group or g == group)]
        if not hits:
            raise KeyError(key)
        if len({g for _, g, _, _ in hits}) > 1:
            groups = sorted({g for _, g, _, _ in hits})
            raise KeyError(f"{key!r} is in several groups {groups}; qualify it as 'group.{name}'")
        return hits[-1]

    def __contains__(self, key: str) -> bool:
        try:
            self._find(key)
            return True
        except KeyError:
            return False

    def get(self, key: str) -> str:
        i, _, _, m = self._find(key)
        body = self._lines[i].rstrip("\r\n")
        value, _ = self._split_comment(body[m.end():])
        return value.strip()

    @staticmethod
    def format_value(value) -> str:
        if isinstance(value, str):
            if '"' in value:
                raise ValueError("namelist strings cannot contain a double quote")
            return f'"{value}"'
        if isinstance(value, (bool, np.bool_)):
            return ".true." if value else ".false."
        if _is_sequence(value):
            return ", ".join(format_number(v) for v in value)
        return format_number(value)

    def set(self, key: str, value) -> None:
        """Replace ``key``'s value in place, keeping the alignment of any comment."""
        i, _, _, m = self._find(key)
        line = self._lines[i]
        body = line.rstrip("\r\n")
        ending = line[len(body):]
        old, comment = self._split_comment(body[m.end():])
        new = self.format_value(value)
        pad = len(old) - len(new)
        # Keep a comment in its column when the new value fits; otherwise one space.
        gap = " " * pad if pad >= 1 else (" " if comment else "")
        self._lines[i] = body[:m.end()] + new + (gap if comment else "") + comment + ending

    def to_text(self) -> str:
        return "".join(self._lines)

    def write(self, path: Optional[PathLike] = None) -> Path:
        dest = Path(path) if path is not None else self.path
        if dest is None:
            raise ValueError("no path given and the config was not read from a file")
        _write_text(dest, self.to_text())
        return dest


# --------------------------------------------------------------------------
# TOPMODEL (.run file + positional params.dat)
# --------------------------------------------------------------------------


class TopmodelConfig:
    """TOPMODEL's ``.run`` file and the ``params.dat`` it names.

    ``.run`` layout (one item per line, ``topmodel.c``/``bmi_topmodel.c``):

    0. stand-alone flag: ``1`` reads forcing from the inputs file, ``0`` is
       framework mode (as under ngen), where forcing comes through BMI
    1. title
    2. inputs file, 3. subcatchment file, 4. parameters file
    5. output file, 6. hydrograph output file

    The paths are relative to the working directory at ``initialize``, so
    ``read`` needs that directory to find ``params.dat``.

    ``params.dat`` is a title line, then one line of 12 numbers in the fixed
    order of :attr:`PARAMS`. Keys are those column names; ``stand_alone`` and the
    file names are exposed as properties.
    """

    PARAMS = ("szm", "t0", "td", "chv", "rv", "srmax", "Q0", "sr0", "infex", "xk0", "hf", "dth")
    _PATH_LINES = {"inputs_file": 2, "subcat_file": 3, "params_file": 4,
                   "output_file": 5, "hydrograph_file": 6}

    def __init__(self, run_text: str, params_text: str, run_path: Optional[PathLike] = None,
                 workdir: Optional[PathLike] = None):
        self.path = Path(run_path) if run_path is not None else None
        self.workdir = Path(workdir) if workdir is not None else None
        self._run: List[str] = run_text.splitlines(keepends=True)
        if len(self._run) < 7:
            raise ValueError(f"a TOPMODEL .run file has at least 7 lines, got {len(self._run)}")
        self._params: List[str] = params_text.splitlines(keepends=True)
        self._spans()                                   # validate now, not on first get

    @classmethod
    def read(cls, run_path: PathLike, workdir: Optional[PathLike] = None) -> "TopmodelConfig":
        """Read ``run_path`` and the params file it names, resolved from ``workdir``.

        ``workdir`` defaults to the current directory, which is what TOPMODEL
        itself uses at ``initialize``.
        """
        run_text = _read_text(run_path)
        workdir = Path(workdir) if workdir is not None else Path.cwd()
        params_rel = run_text.splitlines()[4].strip()
        return cls(run_text, _read_text(workdir / params_rel), run_path, workdir)

    # ---- .run items
    def _run_item(self, index: int) -> str:
        return self._run[index].strip()

    def _set_run_item(self, index: int, text: str) -> None:
        line = self._run[index]
        ending = line[len(line.rstrip("\r\n")):]
        self._run[index] = text + (ending or "\n")

    @property
    def stand_alone(self) -> bool:
        return self._run_item(0) == "1"

    @stand_alone.setter
    def stand_alone(self, value: bool) -> None:
        self._set_run_item(0, "1" if value else "0")

    def __getattr__(self, name):
        if name in TopmodelConfig._PATH_LINES:
            return self._run_item(TopmodelConfig._PATH_LINES[name])
        raise AttributeError(name)

    def set_path(self, item: str, path: str) -> None:
        """Point ``item`` (e.g. ``"params_file"``) at ``path``, as written in the .run file."""
        if item not in self._PATH_LINES:
            raise KeyError(f"{item!r}; expected one of {sorted(self._PATH_LINES)}")
        if any(c.isspace() for c in str(path)):
            raise ValueError("TOPMODEL reads paths with fscanf %s; they cannot contain spaces")
        self._set_run_item(self._PATH_LINES[item], str(path))

    # ---- params.dat columns
    def _spans(self) -> List[Tuple[int, int]]:
        if len(self._params) < 2:
            raise ValueError("params.dat needs a title line and a line of values")
        spans = [m.span() for m in re.finditer(r"\S+", self._params[1])]
        if len(spans) < len(self.PARAMS):
            raise ValueError(f"params.dat line 2 has {len(spans)} values, "
                             f"expected {len(self.PARAMS)} ({' '.join(self.PARAMS)})")
        return spans

    def keys(self) -> List[str]:
        return list(self.PARAMS)

    def __contains__(self, key: str) -> bool:
        return key in self.PARAMS

    def _index(self, key: str) -> int:
        try:
            return self.PARAMS.index(key)
        except ValueError:
            raise KeyError(f"{key!r} is not a params.dat column ({' '.join(self.PARAMS)})") from None

    def get(self, key: str) -> str:
        start, end = self._spans()[self._index(key)]
        return self._params[1][start:end]

    def set(self, key: str, value) -> None:
        text = value if isinstance(value, str) else format_number(value)
        if not text or any(c.isspace() for c in text):
            raise ValueError(f"invalid params.dat value {text!r}")
        start, end = self._spans()[self._index(key)]
        line = self._params[1]
        # Keep the column layout: take the width out of the following spaces when
        # the new text is longer, and pad with spaces when it is shorter.
        after = line[end:]
        grow = len(text) - (end - start)
        if grow > 0:
            spaces = len(after) - len(after.lstrip(" "))
            after = after[min(grow, max(spaces - 1, 0)):] if after.strip() else after
        elif grow < 0:
            after = " " * (-grow) + after if after.strip() else after
        self._params[1] = line[:start] + text + after

    def run_text(self) -> str:
        return "".join(self._run)

    def params_text(self) -> str:
        return "".join(self._params)

    def to_text(self) -> str:
        """The ``.run`` file text (see :meth:`params_text` for ``params.dat``)."""
        return self.run_text()

    def write(self, run_path: Optional[PathLike] = None, params_path: Optional[PathLike] = None,
              workdir: Optional[PathLike] = None) -> Path:
        """Write the ``.run`` file and ``params.dat``.

        ``params_path`` is where to write ``params.dat``. When it is given, the
        ``.run`` file is pointed at it: relative to ``workdir`` if it lies under
        it, absolute otherwise. When omitted, ``params.dat`` is written back to
        the path the ``.run`` file already names, resolved from ``workdir``.
        ``workdir`` defaults to the one given to :meth:`read`.
        """
        run_dest = Path(run_path) if run_path is not None else self.path
        if run_dest is None:
            raise ValueError("no run_path given and the config was not read from a file")
        base = Path(workdir) if workdir is not None else (self.workdir or Path.cwd())
        if params_path is not None:
            params_dest = Path(params_path)
            try:
                rel = os.path.relpath(params_dest.resolve(), base.resolve())
                ref = rel if not rel.startswith("..") else str(params_dest.resolve())
            except ValueError:                                  # different drive (Windows)
                ref = str(params_dest.resolve())
            self.set_path("params_file", ref)
        else:
            params_dest = base / self.params_file
        _write_text(params_dest, self.params_text())
        _write_text(run_dest, self.run_text())
        return run_dest


def open_config(codec: str, path: PathLike, workdir: Optional[PathLike] = None):
    """Read ``path`` with the codec named ``codec`` (a class name in this module)."""
    cls = {"KeyValueConfig": KeyValueConfig, "NamelistConfig": NamelistConfig,
           "TopmodelConfig": TopmodelConfig}[codec]
    if cls is TopmodelConfig:
        return cls.read(path, workdir)
    return cls.read(path)

