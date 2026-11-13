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
    as in Fortran. Only ``name = value`` assignments inside a group
    (``&group`` ... ``/``) are recognized. Outside quotes, a value ends at a
    ``!`` comment, at the group terminator ``/``, or where the next
    ``name =`` on the same line starts; a value may continue on the following
    lines (``a = 1, 2,`` then ``3, 4``). ``set`` writes the whole new value on
    the first line and removes the continuation values. Strings are written
    double-quoted, and lists comma-separated.

    Array-element assignments (``a(2) = ...``) are recognized so that they are
    never mistaken for part of another value, and they are kept as written.
    They cannot be read or set: ``get``/``set`` of a name that also has element
    assignments raise ``KeyError``, because Fortran would apply the element
    assignment over whatever whole value is written.

    This codec covers the namelist only. Noah's parameter tables
    (``SOILPARM.TBL`` etc.) are a different format and are out of scope.
    """

    _GROUP = re.compile(r"\s*&(?P<name>\w+)")
    # A whole-variable assignment, an array-element one (key "a(2)"), and the start
    # of either: what ends the previous value on the same line.
    _ASSIGN = re.compile(r"[\s,]*(?P<key>[A-Za-z]\w*)\s*=\s*")
    _ELEMENT = re.compile(r"[\s,]*(?P<key>[A-Za-z]\w*\s*\([^()=]*\))\s*=\s*")
    _NEXT = re.compile(r"[\s,]*[A-Za-z]\w*\s*(?:\([^()=]*\)\s*)?=")

    def __init__(self, text: str, path: Optional[PathLike] = None):
        self.path = Path(path) if path is not None else None
        self._lines: List[str] = text.splitlines(keepends=True)

    @classmethod
    def read(cls, path: PathLike) -> "NamelistConfig":
        return cls(_read_text(path), path)

    @classmethod
    def _scan(cls, body: str, pos: int) -> Tuple[int, str]:
        """End of the value that starts at ``pos``, and what ends it.

        The second item is ``"!"`` (comment), ``"/"`` (group end), ``"="``
        (another ``name =`` follows on the line) or ``""`` (end of line).
        Characters inside quotes never end a value.
        """
        quote = None
        for i in range(pos, len(body)):
            ch = body[i]
            if quote:
                if ch == quote:
                    quote = None
            elif ch in "\"'":
                quote = ch
            elif ch in "!/":
                return i, ch
            elif ch in ", \t" and cls._NEXT.match(body, i):
                return i, "="
        return len(body), ""

    def _entries(self) -> List[Tuple[str, str, List[Tuple[int, int, int]]]]:
        """``(group, key, spans)`` for every assignment, in file order.

        ``spans`` holds one ``(line index, start, end)`` per line the value is
        written on: the first line, then any continuation lines. An
        array-element assignment has a key such as ``"zsoil(2)"``.
        """
        entries: List[Tuple[str, str, List[Tuple[int, int, int]]]] = []
        group: Optional[str] = None
        current = None                  # the entry a continuation line extends
        for i, line in enumerate(self._lines):
            body = line.rstrip("\r\n")
            pos = 0
            if group is None:
                g = self._GROUP.match(body)
                if not g:
                    continue
                group, current, pos = g.group("name").lower(), None, g.end()
            while group is not None:
                m = self._ASSIGN.match(body, pos) or self._ELEMENT.match(body, pos)
                if m:
                    key = re.sub(r"\s+", "", m.group("key").lower())
                    current = (group, key, [])
                    entries.append(current)
                    start = m.end()
                else:
                    rest = body[pos:].lstrip()
                    if not rest or rest.startswith("!"):
                        break
                    if rest.startswith("&"):
                        g = self._GROUP.match(body, pos)
                        if g and g.group("name").lower() != "end":
                            group, current, pos = g.group("name").lower(), None, g.end()
                            continue
                    if rest.startswith(("/", "&")):
                        group = current = None      # "/", or an old-style "&end"
                        break
                    if current is None:
                        break                       # stray text: not a value we know
                    start = len(body) - len(rest)
                end, stop = self._scan(body, start)
                current[2].append((i, start, end))
                if stop == "/":
                    group = current = None
                elif stop == "=":
                    pos = end
                    continue
                break
        return entries

    def keys(self) -> List[str]:
        """Keys ``get``/``set`` accept: not array elements, nor names that also have them."""
        entries = self._entries()
        element_of = {(g, k.split("(")[0]) for g, k, _ in entries if "(" in k}
        return [f"{g}.{k}" for g, k, _ in entries if "(" not in k and (g, k) not in element_of]

    def _find(self, key: str) -> List[Tuple[int, int, int]]:
        key = key.lower()
        group, _, name = key.rpartition(".")
        if "(" in name:
            raise KeyError(f"{key!r}: array-element assignments cannot be read or set")
        entries = self._entries()
        hits = [(g, spans) for g, k, spans in entries
                if k == name and (not group or g == group)]
        if not hits:
            raise KeyError(key)
        if len({g for g, _ in hits}) > 1:
            groups = sorted({g for g, _ in hits})
            raise KeyError(f"{key!r} is in several groups {groups}; qualify it as 'group.{name}'")
        found_group = hits[-1][0]
        elements = [k for g, k, _ in entries if g == found_group and k.startswith(name + "(")]
        if elements:
            raise KeyError(f"{key!r} is also assigned element by element ({', '.join(elements)}); "
                           f"that is not supported")
        return hits[-1][1]

    def __contains__(self, key: str) -> bool:
        try:
            self._find(key)
            return True
        except KeyError:
            return False

    def get(self, key: str) -> str:
        """The value as written; a value on several lines is joined with spaces."""
        parts = [self._lines[i].rstrip("\r\n")[start:end].strip()
                 for i, start, end in self._find(key)]
        return " ".join(p for p in parts if p)

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
        """Replace ``key``'s value in place.

        Whatever follows the value on its line (a comment, the group's ``/``,
        another assignment) is kept, and a comment or ``/`` stays in its column
        when the new value fits. Continuation lines of the old value are
        removed, keeping anything else written on them.
        """
        new = self.format_value(value)
        (i, start, end), *more = self._find(key)
        for j, s, e in reversed(more):
            line = self._lines[j]
            body = line.rstrip("\r\n")
            left = body[:s] + body[e:]
            if left.strip():
                self._lines[j] = left + line[len(body):]
            else:
                del self._lines[j]
        line = self._lines[i]
        body = line.rstrip("\r\n")
        old, tail = body[start:end], body[end:]
        if tail[:1] in ("!", "/"):
            pad = len(old) - len(new)
            gap = " " * pad if pad >= 1 else " "
        else:                           # end of line, or whitespace/comma before the next name
            gap = ""
        self._lines[i] = body[:start] + new + gap + tail + line[len(body):]

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
    ``read`` needs that directory to find ``params.dat`` (by default the
    directory containing the ``.run`` file).

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

        TOPMODEL resolves these paths from the current directory at
        ``initialize``. ``workdir`` defaults to the directory containing
        ``run_path``, the same default :meth:`bmi_setup.Model.initialize` uses.
        """
        run_text = _read_text(run_path)
        workdir = Path(workdir) if workdir is not None else Path(run_path).resolve().parent
        lines = run_text.splitlines()
        if len(lines) < 7:
            raise ValueError(f"a TOPMODEL .run file has at least 7 lines, got {len(lines)}")
        return cls(run_text, _read_text(workdir / lines[4].strip()), run_path, workdir)

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
    """Read ``path`` with the codec named ``codec`` (a class name in this module).

    ``workdir`` is used by ``TopmodelConfig`` only (default: ``path``'s directory).
    """
    cls = {"KeyValueConfig": KeyValueConfig, "NamelistConfig": NamelistConfig,
           "TopmodelConfig": TopmodelConfig}[codec]
    if cls is TopmodelConfig:
        return cls.read(path, workdir)
    return cls.read(path)

