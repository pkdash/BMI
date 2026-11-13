"""NumPy <-> native BMI buffer rules shared by every pymt_* wrapper.

Single source of truth: ``common/bmi_arrays.py``.  ``common/render_wrappers.py``
copies this file verbatim into each model as ``<MODEL>/wrapper/_bmi_arrays.py``
and ``pymt_<name>/lib/_bmi_arrays.py``.  Edit it here and re-run that script;
do not edit the copies.

Why this exists
---------------
Native BMI ``get_value``/``set_value`` implementations copy exactly
``get_var_nbytes(name)`` bytes to or from the pointer they are given, using the
element type reported by ``get_var_type``/``get_var_itemsize``.  A Python
wrapper therefore has to hand over a C-contiguous buffer of exactly that dtype
and at least that size; anything else silently corrupts data or reads/writes
out of bounds.  The functions below derive the dtype and element count from
the native metadata and validate (or safely convert) the arrays crossing the
boundary.  They are pure NumPy so they can be unit tested without any model.
"""

import numpy as np

__all__ = [
    "resolve_dtype",
    "var_layout",
    "prepare_dest",
    "prepare_src",
    "prepare_indices",
    "check_status",
]

# Normalized BMI type name -> NumPy kind ("f" float, "i" signed int,
# "u" unsigned int, "b" bool).  Names are the spellings that C, C++ and
# Fortran BMI implementations actually report from get_var_type.
_KIND = {
    # floating point
    "double": "f",
    "float": "f",
    "long double": "f",
    "real": "f",
    "double precision": "f",
    # signed integers
    "char": "i",
    "signed char": "i",
    "short": "i",
    "short int": "i",
    "int": "i",
    "signed int": "i",
    "long": "i",
    "long int": "i",
    "long long": "i",
    "long long int": "i",
    "integer": "i",
    "int8_t": "i",
    "int16_t": "i",
    "int32_t": "i",
    "int64_t": "i",
    # unsigned integers
    "unsigned char": "u",
    "unsigned short": "u",
    "unsigned short int": "u",
    "unsigned": "u",
    "unsigned int": "u",
    "unsigned long": "u",
    "unsigned long int": "u",
    "unsigned long long": "u",
    "unsigned long long int": "u",
    "uint8_t": "u",
    "uint16_t": "u",
    "uint32_t": "u",
    "uint64_t": "u",
    "size_t": "u",
    # booleans
    "bool": "b",
    "logical": "b",
}

# Names whose width is fixed by the language (or by the name itself).  For
# every other name ("int", "long", "real", "integer", ...) the width comes
# from the native get_var_itemsize, which is the only reliable authority
# (C long is 4 bytes on Windows; Fortran "real" is 8 bytes with -fdefault-real-8).
_FIXED_SIZE = {
    "double": 8,
    "float": 4,
    "double precision": 8,
    "char": 1,
    "signed char": 1,
    "unsigned char": 1,
    "short": 2,
    "short int": 2,
    "unsigned short": 2,
    "unsigned short int": 2,
    "int8_t": 1,
    "int16_t": 2,
    "int32_t": 4,
    "int64_t": 8,
    "uint8_t": 1,
    "uint16_t": 2,
    "uint32_t": 4,
    "uint64_t": 8,
}


def _normalize(type_name):
    if isinstance(type_name, bytes):
        type_name = type_name.decode("ascii", "replace")
    name = " ".join(str(type_name).replace("\x00", " ").split()).lower()
    if name.startswith("std::"):
        name = name[len("std::"):]
    return name


def _kind_and_fixed_size(name):
    """Return (kind, fixed_size or None) for a normalized type name."""
    if name in _KIND:
        return _KIND[name], _FIXED_SIZE.get(name)

    # Fortran declarations with an explicit width: real*8, integer*4, ...
    for prefix, kind in (("real*", "f"), ("integer*", "i"), ("logical*", "b")):
        if name.startswith(prefix):
            try:
                return kind, int(name[len(prefix):])
            except ValueError:
                break

    # Fortran kind selectors: real(8), real(kind=8), real(c_double), ...
    for prefix, kind in (("real(", "f"), ("integer(", "i"), ("logical(", "b")):
        if name.startswith(prefix) and name.endswith(")"):
            return kind, None

    # NumPy spellings (float64, int32, uint8, bool_, ...).  Only accepted when
    # they carry an explicit width so that "int"/"float"-style ambiguity
    # cannot sneak in through NumPy's own aliases.
    if any(ch.isdigit() for ch in name) or name in ("bool_", "bool8"):
        try:
            dt = np.dtype(name)
        except TypeError:
            return None, None
        if dt.kind in "fiub":
            return dt.kind, dt.itemsize

    return None, None


def resolve_dtype(type_name, itemsize):
    """Map a native BMI type name plus its native item size to a NumPy dtype.

    The kind (float/int/unsigned/bool) comes from the type name and the width
    from ``itemsize`` as reported by the native ``get_var_itemsize``.

    Raises
    ------
    TypeError
        If the type name is not recognised, or if it contradicts ``itemsize``
        (e.g. ``"double"`` reported with an item size of 4).
    """
    name = _normalize(type_name)
    try:
        itemsize = int(itemsize)
    except (TypeError, ValueError):
        raise TypeError(f"invalid BMI item size {itemsize!r} for type {type_name!r}")
    if itemsize <= 0:
        raise TypeError(f"invalid BMI item size {itemsize} for type {type_name!r}")

    kind, fixed = _kind_and_fixed_size(name)
    if kind is None:
        raise TypeError(f"unsupported BMI variable type {type_name!r}")
    if fixed is not None and fixed != itemsize:
        raise TypeError(
            f"BMI type {type_name!r} is {fixed} bytes wide but the model "
            f"reports an item size of {itemsize}"
        )

    if kind == "b" and itemsize != 1:
        # NumPy bools are 1 byte; Fortran default logical is 4.  Expose wider
        # logicals as integers of the same width (0 = false, non-zero = true).
        kind = "i"
    try:
        dtype = np.dtype(f"{kind}{itemsize}")
    except TypeError:
        raise TypeError(
            f"no NumPy dtype for BMI type {type_name!r} with item size {itemsize}"
        )
    return dtype


def var_layout(type_name, itemsize, nbytes):
    """Return ``(dtype, count)`` for a BMI variable.

    ``count`` is ``nbytes // itemsize``: the number of elements the native
    get_value/set_value will copy.  It deliberately does *not* come from
    ``get_grid_size``: several models report variables whose length differs
    from their grid size (or that have no grid at all).
    """
    dtype = resolve_dtype(type_name, itemsize)
    nbytes = int(nbytes)
    if nbytes < 0:
        raise ValueError(f"invalid BMI nbytes {nbytes} for type {type_name!r}")
    if nbytes % dtype.itemsize:
        raise ValueError(
            f"BMI nbytes {nbytes} is not a multiple of the item size "
            f"{dtype.itemsize} for type {type_name!r}"
        )
    return dtype, nbytes // dtype.itemsize


def _label(name):
    return f"{name!r}: " if name is not None else ""


def prepare_dest(dest, dtype, count, name=None):
    """Return a buffer the native code may fill with ``count`` items of ``dtype``.

    With ``dest=None`` a new 1-D array is allocated, pre-filled with NaN for
    floating-point variables (zeros otherwise) so that any element a native
    get_value leaves unwritten is recognisable rather than a plausible value.
    A caller-supplied array is filled in place, so it must already have exactly
    ``dtype``, be C-contiguous and writeable, and hold at least ``count`` items;
    it is never converted, because a converted copy would not be the caller's
    array.
    """
    dtype = np.dtype(dtype)
    if dest is None:
        if dtype.kind == "f":
            return np.full(count, np.nan, dtype=dtype)
        return np.zeros(count, dtype=dtype)
    if not isinstance(dest, np.ndarray):
        raise TypeError(
            f"{_label(name)}dest must be a numpy.ndarray, not "
            f"{type(dest).__name__}; call get_value(name) to allocate one"
        )
    if dest.dtype != dtype:
        raise TypeError(
            f"{_label(name)}dest has dtype {dest.dtype} but the variable is "
            f"{dtype}; allocate it with np.empty({count}, dtype={str(dtype)!r})"
        )
    if not dest.flags["C_CONTIGUOUS"]:
        raise ValueError(f"{_label(name)}dest must be C-contiguous")
    if not dest.flags["WRITEABLE"]:
        raise ValueError(f"{_label(name)}dest must be writeable")
    if dest.size < count:
        raise ValueError(
            f"{_label(name)}dest holds {dest.size} items but the variable "
            f"has {count}"
        )
    return dest


def _fits_integer_range(arr, dtype):
    if arr.size == 0:
        return True
    info = np.iinfo(dtype)
    return int(arr.min()) >= info.min and int(arr.max()) <= info.max


def prepare_src(src, dtype, count, name=None):
    """Return a C-contiguous 1-D array of exactly ``count`` items of ``dtype``.

    Accepts arrays, lists and scalars.  Values are converted only when the
    conversion cannot change their meaning: NumPy ``same_kind`` casting
    (int -> float, float64 -> float32, ...), plus integer -> integer when
    every value fits the target range.  Anything else (float -> int,
    complex, strings, objects) raises TypeError.  A size mismatch raises
    ValueError, because the native code copies exactly ``count`` items.
    """
    dtype = np.dtype(dtype)
    arr = np.asarray(src)
    if arr.dtype != dtype:
        src_int = arr.dtype.kind in "biu"
        dst_int = dtype.kind in "iu"
        if src_int and dst_int:
            if not _fits_integer_range(arr, dtype):
                raise TypeError(
                    f"{_label(name)}values do not fit in the variable's "
                    f"dtype {dtype}"
                )
        elif not np.can_cast(arr.dtype, dtype, casting="same_kind"):
            raise TypeError(
                f"{_label(name)}cannot safely convert {arr.dtype} values to "
                f"the variable's dtype {dtype}"
            )
        arr = arr.astype(dtype)
    arr = np.ascontiguousarray(arr).reshape(-1)
    if arr.size != count:
        raise ValueError(
            f"{_label(name)}expected {count} value(s), got {arr.size}"
        )
    return arr


def prepare_indices(inds, count, name=None):
    """Return ``inds`` as a C-contiguous 1-D array of C ``int``.

    Accepts any integer array-like (e.g. the default int64 arrays NumPy
    creates); every index must address one of the ``count`` elements.
    """
    arr = np.asarray(inds)
    if arr.size == 0:
        return np.zeros(0, dtype=np.intc)
    if arr.dtype.kind not in "iu":
        raise TypeError(f"{_label(name)}indices must be integers, not {arr.dtype}")
    arr = arr.reshape(-1)
    if int(arr.min()) < 0 or int(arr.max()) >= count:
        raise IndexError(
            f"{_label(name)}indices must be in [0, {count}); got "
            f"min={int(arr.min())}, max={int(arr.max())}"
        )
    return np.ascontiguousarray(arr, dtype=np.intc)


def check_status(status, func, name=None):
    """Raise RuntimeError if a native BMI call returned a non-zero status."""
    if status != 0:
        target = f"({name!r})" if name is not None else ""
        raise RuntimeError(f"BMI {func}{target} failed with status {status}")
