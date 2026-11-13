# Shared Cython helper included by every generated pymt_*/lib/*.pyx.
#
# Single source of truth: common/bmi_ptr.pxi.  common/render_wrappers.py copies
# it next to each model's .pyx; edit it here and re-run that script.

cimport numpy as cnp

cnp.import_array()


cdef object wrap_native_ptr(object owner, void *ptr, object dtype,
                            Py_ssize_t count, object name):
    """Return a NumPy view of ``count`` items of ``dtype`` at native ``ptr``.

    The view does not copy: writes through it change the model state, which
    is what BMI get_value_ptr promises.  Its base object is ``owner`` (the
    wrapper instance), so the model cannot be garbage-collected, and its
    memory freed, while any view is alive.

    The view is still only valid while the model keeps that allocation: it
    becomes dangling after ``finalize()``, and after any native call that
    reallocates the variable (e.g. dynamic wetting-front arrays).  Fetch a
    fresh pointer after such calls.
    """
    if count == 0:
        # Empty variables (e.g. zero wetting fronts) may legitimately have no
        # storage, so a NULL pointer is fine here.
        return np.empty(0, dtype=dtype)
    if ptr == NULL:
        raise RuntimeError(
            f"BMI get_value_ptr({name!r}) returned a NULL pointer"
        )
    cdef cnp.dtype dt = np.dtype(dtype)
    cdef cnp.npy_intp dims[1]
    dims[0] = <cnp.npy_intp>count
    cdef cnp.ndarray arr = cnp.PyArray_SimpleNewFromData(1, dims, dt.type_num, ptr)
    cnp.set_array_base(arr, owner)
    return arr
