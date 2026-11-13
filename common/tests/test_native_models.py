"""BMI value-exchange contract tests against the real native model libraries.

Each model is tested only when its wrapper is importable *and* a config file
is given through the environment:

    PYMT_<KEY>_CONFIG   path to the model's BMI init/config file (required)
    PYMT_<KEY>_WORKDIR  directory to chdir into before initialize (optional;
                        defaults to the config file's directory)

<KEY> is one of the keys of WRAPPERS below, e.g.

    PYMT_CFE_CONFIG=/path/to/cfe/configs/cfe_config_laramie_pass_aet_rz.txt \\
        python -m pytest common/tests/test_native_models.py -v

Run the whole suite once per model image (or on JupyterHub, where several
models are installed).  Tests that need a feature the native model does not
implement (e.g. Fortran get_value_ptr) are skipped with the native reason.
"""

import gc
import importlib
import os
from contextlib import contextmanager
from pathlib import Path

import numpy as np
import pytest

# key -> (package, class name)
WRAPPERS = {
    "CFE": ("pymt_cfe", "CFE"),
    "PET": ("pymt_pet", "PET"),
    "TOPMODEL": ("pymt_topmodel", "TOPMODEL"),
    "SFT": ("pymt_sft", "SFT"),
    "SMP": ("pymt_smp", "SMP"),
    "LASAM": ("pymt_lasam", "LASAM"),
    "UEB": ("pymt_ueb", "UEB"),
    "NOAH_OWP": ("pymt_noah_owp", "NOAH_OWP"),
    "SAC_SMA": ("pymt_sac_sma", "SAC_SMA"),
    "SNOW17": ("pymt_snow17", "SNOW17"),
}

# Documented behavior of the *native* libraries that the wrapper must not
# paper over.  (model key, variable) -> reason.
NATIVE_GET_VALUE_FIRST_ELEMENT_ONLY = {
    ("CFE", "soil_moisture_profile"):
        "native CFE Get_value calls Get_value_at_indices(name, dest, {0}, 1), "
        "so only element 0 is copied (src/bmi_cfe.c); use get_value_ptr",
}


def _configured():
    params = []
    for key, (package, cls) in WRAPPERS.items():
        config = os.environ.get(f"PYMT_{key}_CONFIG")
        marks = []
        if not config:
            marks.append(pytest.mark.skip(reason=f"PYMT_{key}_CONFIG not set"))
        params.append(pytest.param(key, id=key, marks=marks))
    return params


@contextmanager
def _workdir(path):
    previous = os.getcwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(previous)


def _new_model(key):
    package, cls = WRAPPERS[key]
    try:
        module = importlib.import_module(package)
    except ImportError as err:
        # A config was provided, so the model is expected to be testable.
        pytest.fail(f"PYMT_{key}_CONFIG is set but {package} cannot be imported: {err}")
    return getattr(module, cls)()


def _config_and_workdir(key):
    config = Path(os.environ[f"PYMT_{key}_CONFIG"]).resolve()
    workdir = Path(os.environ.get(f"PYMT_{key}_WORKDIR", config.parent)).resolve()
    return str(config), workdir


@pytest.fixture(params=_configured())
def key(request):
    return request.param


@pytest.fixture
def model_key_pair(key):
    """(key, initialized model) for tests that need both."""
    config, workdir = _config_and_workdir(key)
    with _workdir(workdir):
        m = _new_model(key)
        m.initialize(config)
        yield key, m
        try:
            m.finalize()
        except RuntimeError:
            pass


@pytest.fixture
def initialized(key):
    config, workdir = _config_and_workdir(key)
    with _workdir(workdir):
        m = _new_model(key)
        m.initialize(config)
        yield m
        try:
            m.finalize()
        except RuntimeError:
            pass


def _variables(m):
    return list(dict.fromkeys(m.get_input_var_names() + m.get_output_var_names()))


def _layout(m, name):
    dtype = np.dtype(m.get_var_type(name))
    count = m.get_var_nbytes(name) // m.get_var_itemsize(name)
    return dtype, count


def _try_ptr(m, name):
    """Return a get_value_ptr view, or None if the native model has none."""
    try:
        return m.get_value_ptr(name)
    except NotImplementedError:
        return None
    except RuntimeError:
        # Native get_value_ptr reported failure for this variable.
        return None


def _read_back(m, name):
    """Current values, preferring the pointer (complete for every variable)."""
    ptr = _try_ptr(m, name)
    return np.array(ptr, copy=True) if ptr is not None else m.get_value(name)


def _new_values(dtype, current):
    if dtype.kind == "f":
        return (current + 0.25).astype(dtype)
    if dtype.kind in "iu":
        return (current + 1).astype(dtype)
    if dtype.kind == "b":
        return np.logical_not(current)
    raise AssertionError(f"unexpected dtype {dtype}")


def _failures_message(failures):
    return "\n".join(f"  {name}: {msg}" for name, msg in failures)


# --------------------------------------------------------------------------- #
# Generic contract (every configured model, every exchange item)
# --------------------------------------------------------------------------- #

def test_metadata_is_consistent(initialized):
    m = initialized
    failures = []
    for name in _variables(m):
        try:
            dtype = np.dtype(m.get_var_type(name))
            itemsize = m.get_var_itemsize(name)
            nbytes = m.get_var_nbytes(name)
            if dtype.itemsize != itemsize:
                failures.append((name, f"dtype {dtype} vs itemsize {itemsize}"))
            if nbytes % itemsize:
                failures.append((name, f"nbytes {nbytes} not a multiple of {itemsize}"))
        except Exception as err:  # noqa: BLE001 - report every variable
            failures.append((name, repr(err)))
    assert not failures, "\n" + _failures_message(failures)


def test_get_value_allocates_and_fills_dest(model_key_pair):
    key, m = model_key_pair
    for name in _variables(m):
        dtype, count = _layout(m, name)
        allocated = m.get_value(name)
        assert allocated.dtype == dtype and allocated.shape == (count,), name
        dest = np.zeros(count, dtype=dtype)
        assert m.get_value(name, dest) is dest, name
        # Only compare what the native get_value actually writes.
        n = 1 if (key, name) in NATIVE_GET_VALUE_FIRST_ELEMENT_ONLY else count
        np.testing.assert_array_equal(dest[:n], allocated[:n], err_msg=name)


def test_get_value_rejects_bad_dest_without_crashing(initialized):
    m = initialized
    for name in _variables(m):
        dtype, count = _layout(m, name)
        wrong = np.float32 if dtype != np.float32 else np.float64
        with pytest.raises(TypeError):
            m.get_value(name, np.zeros(count, dtype=wrong))
        with pytest.raises(TypeError):
            m.get_value(name, [0.0] * count)
        if count > 0:
            with pytest.raises(ValueError):
                m.get_value(name, np.zeros(count - 1, dtype=dtype))
        if count > 1:  # NumPy treats any 1-element view as contiguous
            with pytest.raises(ValueError):
                m.get_value(name, np.zeros(2 * count, dtype=dtype)[::2])


def test_get_value_ptr_is_a_live_view(model_key_pair):
    key, m = model_key_pair
    checked = 0
    for name in _variables(m):
        dtype, count = _layout(m, name)
        ptr = _try_ptr(m, name)
        if ptr is None:
            continue
        checked += 1
        assert ptr.dtype == dtype and ptr.shape == (count,), name
        assert ptr.base is m, f"{name}: view must keep the model alive"
        if (key, name) not in NATIVE_GET_VALUE_FIRST_ELEMENT_ONLY:
            np.testing.assert_array_equal(ptr, m.get_value(name), err_msg=name)
        else:
            np.testing.assert_array_equal(ptr[:1], m.get_value(name)[:1], err_msg=name)
        if count and name in m.get_input_var_names():
            # Writes through the view are model writes, and vice versa.
            saved = ptr.copy()
            ptr[0] = _new_values(dtype, ptr[:1])[0]
            assert m.get_value(name)[0] == ptr[0], name
            m.set_value(name, saved)
            # Re-fetch: a native set_value may reallocate the variable (SMP's
            # ResetSize does for the wetting-front arrays), which invalidates
            # the old view.  That is documented get_value_ptr behavior.
            np.testing.assert_array_equal(_read_back(m, name), saved, err_msg=name)
    if checked == 0:
        pytest.skip("native model exposes no pointers (get_value_ptr unsupported)")


def test_known_native_get_value_limits(model_key_pair):
    """Pin the documented native behavior so a native fix gets noticed."""
    key, m = model_key_pair
    names = [n for (k, n) in NATIVE_GET_VALUE_FIRST_ELEMENT_ONLY if k == key]
    if not names:
        pytest.skip("no documented native get_value limits for this model")
    for name in names:
        dtype, count = _layout(m, name)
        if count < 2:
            continue
        values = np.arange(1, count + 1, dtype=dtype)
        m.set_value(name, values)
        np.testing.assert_array_equal(_read_back(m, name), values)
        got = m.get_value(name)
        assert got[0] == values[0]
        # Elements the native code does not write stay NaN (not plausible zeros).
        assert np.isnan(got[1:]).all(), NATIVE_GET_VALUE_FIRST_ELEMENT_ONLY[(key, name)]


def test_set_value_round_trip(model_key_pair):
    key, m = model_key_pair
    for name in m.get_input_var_names():
        dtype, count = _layout(m, name)
        if count == 0:
            continue
        current = _read_back(m, name)
        new = _new_values(dtype, current)
        m.set_value(name, new)
        np.testing.assert_array_equal(_read_back(m, name), new, err_msg=name)

        # Lists and (for scalars) plain Python numbers are accepted.
        m.set_value(name, current.tolist())
        np.testing.assert_array_equal(_read_back(m, name), current, err_msg=name)
        if count == 1:
            m.set_value(name, new.item())
            np.testing.assert_array_equal(_read_back(m, name), new, err_msg=name)


def test_set_value_rejects_bad_src_without_crashing(initialized):
    m = initialized
    for name in m.get_input_var_names():
        dtype, count = _layout(m, name)
        if count == 0:
            continue
        before = _read_back(m, name)
        with pytest.raises(ValueError):
            m.set_value(name, np.zeros(count + 1, dtype=dtype))
        if count > 1:
            # The old wrappers passed a 1-element buffer straight to a native
            # memcpy of nbytes: a heap over-read.
            with pytest.raises(ValueError):
                m.set_value(name, np.zeros(1, dtype=dtype))
        if dtype.kind in "iu":
            with pytest.raises(TypeError):
                m.set_value(name, np.full(count, 1.5))
        with pytest.raises(TypeError):
            m.set_value(name, ["x"] * count)
        np.testing.assert_array_equal(_read_back(m, name), before, err_msg=name)


def test_value_at_indices_round_trip(model_key_pair):
    key, m = model_key_pair
    for name in m.get_input_var_names():
        dtype, count = _layout(m, name)
        if count == 0:
            continue
        current = _read_back(m, name)
        last = np.array([count - 1], dtype=np.int64)  # default-int indices accepted
        new = _new_values(dtype, current[last])
        m.set_value_at_indices(name, last, new)
        expected = current.copy()
        expected[last] = new
        np.testing.assert_array_equal(_read_back(m, name), expected, err_msg=name)

        got = m.get_value_at_indices(name, np.zeros(1, dtype=dtype), [0])
        np.testing.assert_array_equal(got, expected[:1], err_msg=name)

        with pytest.raises(IndexError):
            m.get_value_at_indices(name, np.zeros(1, dtype=dtype), [count])
        with pytest.raises(IndexError):
            m.set_value_at_indices(name, [-1], new)


def test_pointer_view_keeps_model_alive(key):
    config, workdir = _config_and_workdir(key)
    with _workdir(workdir):
        m = _new_model(key)
        m.initialize(config)
        view = None
        for name in _variables(m):
            view = _try_ptr(m, name)
            if view is not None:
                break
        if view is None:
            m.finalize()
            pytest.skip("native model exposes no pointers")
        snapshot = np.array(view, copy=True)
        del m
        gc.collect()
        # Without the base reference this would read freed memory.
        np.testing.assert_array_equal(view, snapshot)
        view.base.finalize()


def test_value_access_requires_initialized_model(key):
    config, workdir = _config_and_workdir(key)
    with _workdir(workdir):
        m = _new_model(key)
        with pytest.raises(RuntimeError, match="initialize"):
            m.get_value("anything")
        m.initialize(config)
        name = _variables(m)[0]
        m.get_value(name)
        m.finalize()
        m.finalize()  # idempotent: must not touch released native data
        for call in (lambda: m.get_value(name), lambda: m.set_value(name, 0),
                     lambda: m.update()):
            with pytest.raises(RuntimeError, match="finalize"):
                call()


# --------------------------------------------------------------------------- #
# Model-specific regressions for the defects fixed in the wrappers
# --------------------------------------------------------------------------- #

def _require(key, wanted):
    if key != wanted:
        pytest.skip(f"{wanted}-specific test")


def test_cfe_array_length_comes_from_nbytes_not_grid(model_key_pair):
    key, m = model_key_pair
    _require(key, "CFE")
    name = "soil_moisture_profile"
    count = m.get_var_nbytes(name) // m.get_var_itemsize(name)
    # The variable sits on grid 0 (size 1) but holds n_soil_layers values.
    assert m.get_grid_size(m.get_var_grid(name)) == 1
    assert m.get_value_ptr(name).shape == (count,)
    values = np.linspace(0.1, 0.4, count)
    m.set_value(name, values)
    np.testing.assert_array_equal(m.get_value_ptr(name), values)


def test_cfe_calibration_parameters_without_grid(model_key_pair):
    key, m = model_key_pair
    _require(key, "CFE")
    # Calibratable parameters are not exchange items and have no grid
    # (native get_var_grid fails), but get/set/ptr work through nbytes.
    with pytest.raises(RuntimeError):
        m.get_var_grid("maxsmc")
    m.set_value("maxsmc", 0.4)
    np.testing.assert_array_equal(m.get_value_ptr("maxsmc"), [0.4])
    np.testing.assert_array_equal(m.get_value("maxsmc"), [0.4])


def test_cfe_integer_output_dtype(model_key_pair):
    key, m = model_key_pair
    _require(key, "CFE")
    name = "SURF_RUNOFF_SCHEME"
    assert m.get_var_type(name) == "int32"
    ptr = m.get_value_ptr(name)
    assert ptr.dtype == np.int32
    np.testing.assert_array_equal(ptr, m.get_value(name))


def test_cfe_int_input_is_converted_not_reinterpreted(model_key_pair):
    key, m = model_key_pair
    _require(key, "CFE")
    name = "atmosphere_water__liquid_equivalent_precipitation_rate"
    m.set_value(name, np.array([2], dtype=np.int64))
    np.testing.assert_array_equal(m.get_value(name), [2.0])


def test_noah_owp_reports_missing_pointers_clearly(model_key_pair):
    key, m = model_key_pair
    _require(key, "NOAH_OWP")
    name = m.get_output_var_names()[0]
    with pytest.raises(NotImplementedError, match="get_value"):
        m.get_value_ptr(name)
