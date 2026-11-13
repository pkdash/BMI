"""Unit tests for common/bmi_arrays.py (no native model library required).

Run from the repository root:  python -m pytest common/tests/test_bmi_arrays.py
"""

import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from bmi_arrays import (  # noqa: E402
    check_status,
    prepare_dest,
    prepare_indices,
    prepare_src,
    resolve_dtype,
    var_layout,
)


# --------------------------------------------------------------------------- #
# resolve_dtype
# --------------------------------------------------------------------------- #

@pytest.mark.parametrize(
    "type_name, itemsize, expected",
    [
        # C / C++ spellings
        ("double", 8, "float64"),
        ("float", 4, "float32"),
        ("int", 4, "int32"),
        ("int", 8, "int64"),
        ("long", 8, "int64"),
        ("long", 4, "int32"),  # Windows C long
        ("long int", 8, "int64"),
        ("long long", 8, "int64"),
        ("short", 2, "int16"),
        ("unsigned int", 4, "uint32"),
        ("unsigned long", 8, "uint64"),
        ("unsigned char", 1, "uint8"),
        ("char", 1, "int8"),
        ("uint64_t", 8, "uint64"),
        ("std::int32_t", 4, "int32"),
        ("bool", 1, "bool"),
        # Fortran spellings
        ("real", 4, "float32"),
        ("real", 8, "float64"),  # compiled with -fdefault-real-8
        ("REAL", 4, "float32"),
        ("real*4", 4, "float32"),
        ("real*8", 8, "float64"),
        ("double precision", 8, "float64"),
        ("DOUBLE PRECISION", 8, "float64"),
        ("integer", 4, "int32"),
        ("integer*8", 8, "int64"),
        ("real(kind=8)", 8, "float64"),
        ("logical", 4, "int32"),  # no 4-byte NumPy bool: same-width int
        ("logical", 1, "bool"),
        # NumPy spellings, padding and NULs from fixed-size C buffers
        ("float64", 8, "float64"),
        ("int32", 4, "int32"),
        ("  double  ", 8, "float64"),
        ("double\x00\x00", 8, "float64"),
        (b"double", 8, "float64"),
    ],
)
def test_resolve_dtype(type_name, itemsize, expected):
    if expected is None:
        with pytest.raises(TypeError):
            resolve_dtype(type_name, itemsize)
    else:
        assert resolve_dtype(type_name, itemsize) == np.dtype(expected)


@pytest.mark.parametrize(
    "type_name, itemsize",
    [
        ("double", 4),   # name fixes the width: contradiction
        ("float", 8),
        ("short", 4),
        ("real*8", 4),
        ("int32", 8),
        ("double", 0),
        ("double", -8),
        ("int", 3),      # no such NumPy dtype
        ("string", 8),   # unsupported type
        ("complex", 16),
        ("", 8),
    ],
)
def test_resolve_dtype_rejects(type_name, itemsize):
    with pytest.raises(TypeError):
        resolve_dtype(type_name, itemsize)


# --------------------------------------------------------------------------- #
# var_layout
# --------------------------------------------------------------------------- #

def test_var_layout_scalar_and_array():
    assert var_layout("double", 8, 8) == (np.dtype("float64"), 1)
    # e.g. CFE soil_moisture_profile: grid size 1, but n_soil_layers items
    assert var_layout("double", 8, 32) == (np.dtype("float64"), 4)
    assert var_layout("int", 4, 12) == (np.dtype("int32"), 3)
    assert var_layout("double", 8, 0) == (np.dtype("float64"), 0)


@pytest.mark.parametrize("nbytes", [7, 9, -8])
def test_var_layout_rejects_bad_nbytes(nbytes):
    with pytest.raises(ValueError):
        var_layout("double", 8, nbytes)


# --------------------------------------------------------------------------- #
# prepare_dest
# --------------------------------------------------------------------------- #

def test_prepare_dest_allocates_unwritten_marker():
    out = prepare_dest(None, np.float64, 3)
    assert out.dtype == np.float64 and out.shape == (3,)
    assert np.isnan(out).all()  # unwritten floats are NaN, not plausible zeros
    out = prepare_dest(None, np.int32, 2)
    assert out.dtype == np.int32 and not out.any()


def test_prepare_dest_returns_same_object():
    dest = np.empty(4, dtype=np.int32)
    assert prepare_dest(dest, np.int32, 4) is dest
    # larger is fine (BMI only requires "at least")
    big = np.empty(10, dtype=np.int32)
    assert prepare_dest(big, np.int32, 4) is big
    # multi-dimensional C-contiguous arrays are fine too
    grid = np.empty((2, 3), dtype=np.float64)
    assert prepare_dest(grid, np.float64, 6) is grid


@pytest.mark.parametrize(
    "dest, exc",
    [
        ([0.0], TypeError),                              # not an ndarray
        (np.empty(3, dtype=np.float32), TypeError),     # wrong dtype
        (np.empty(3, dtype=np.int64), TypeError),
        (np.empty(3, dtype=">f8"), TypeError),          # wrong byte order
        (np.empty(2, dtype=np.float64), ValueError),    # too small
        (np.empty(6, dtype=np.float64)[::2], ValueError),  # not contiguous
    ],
)
def test_prepare_dest_rejects(dest, exc):
    with pytest.raises(exc):
        prepare_dest(dest, np.float64, 3, name="var")


def test_prepare_dest_rejects_readonly():
    dest = np.empty(3, dtype=np.float64)
    dest.flags.writeable = False
    with pytest.raises(ValueError):
        prepare_dest(dest, np.float64, 3)


# --------------------------------------------------------------------------- #
# prepare_src
# --------------------------------------------------------------------------- #

@pytest.mark.parametrize(
    "src, dtype, count, expected",
    [
        (0.4, np.float64, 1, [0.4]),                    # Python scalar
        (3, np.float64, 1, [3.0]),                      # int -> float
        ([1.0, 2.0], np.float64, 2, [1.0, 2.0]),        # list
        (np.array([1.5], dtype=np.float32), np.float64, 1, [1.5]),
        (np.array([1.5, 2.5]), np.float32, 2, [1.5, 2.5]),  # float64 -> float32
        (np.array([[1, 2], [3, 4]]), np.int32, 4, [1, 2, 3, 4]),  # 2-D, flattened
        (np.array([7], dtype=np.int64), np.int32, 1, [7]),  # fits int32
        ([5], np.uint32, 1, [5]),                       # signed -> unsigned, fits
        (True, np.int32, 1, [1]),
        (np.arange(6.0)[::2], np.float64, 3, [0.0, 2.0, 4.0]),  # non-contiguous
    ],
)
def test_prepare_src_converts(src, dtype, count, expected):
    out = prepare_src(src, dtype, count)
    assert out.dtype == np.dtype(dtype)
    assert out.ndim == 1 and out.flags["C_CONTIGUOUS"]
    np.testing.assert_array_equal(out, np.asarray(expected, dtype=dtype))


def test_prepare_src_no_copy_when_already_right():
    src = np.array([1.0, 2.0])
    assert np.shares_memory(prepare_src(src, np.float64, 2), src)


@pytest.mark.parametrize(
    "src, dtype, count, exc",
    [
        (1.5, np.int32, 1, TypeError),                   # float -> int is lossy
        (np.array([1.0]), np.int64, 1, TypeError),
        (np.array([2 ** 40]), np.int32, 1, TypeError),   # out of int32 range
        ([-1], np.uint32, 1, TypeError),                  # negative -> unsigned
        (1 + 2j, np.float64, 1, TypeError),
        ("abc", np.float64, 1, TypeError),
        ([1.0, 2.0], np.float64, 1, ValueError),          # too many
        ([1.0], np.float64, 3, ValueError),               # too few (native over-read)
        ([], np.float64, 1, ValueError),
    ],
)
def test_prepare_src_rejects(src, dtype, count, exc):
    with pytest.raises(exc):
        prepare_src(src, dtype, count, name="var")


# --------------------------------------------------------------------------- #
# prepare_indices
# --------------------------------------------------------------------------- #

def test_prepare_indices_accepts_int64():
    out = prepare_indices(np.array([0, 2], dtype=np.int64), 3)
    assert out.dtype == np.intc
    np.testing.assert_array_equal(out, [0, 2])


def test_prepare_indices_list_and_empty():
    np.testing.assert_array_equal(prepare_indices([1], 2), [1])
    out = prepare_indices([], 2)
    assert out.dtype == np.intc and out.size == 0


@pytest.mark.parametrize(
    "inds, exc",
    [
        ([3], IndexError),
        ([-1], IndexError),
        ([0.0], TypeError),
    ],
)
def test_prepare_indices_rejects(inds, exc):
    with pytest.raises(exc):
        prepare_indices(inds, 3)


# --------------------------------------------------------------------------- #
# check_status
# --------------------------------------------------------------------------- #

def test_check_status():
    check_status(0, "get_value", "x")
    with pytest.raises(RuntimeError, match=r"get_value\('x'\) failed with status 1"):
        check_status(1, "get_value", "x")
