# cython: c_string_type=str, c_string_encoding=ascii

import ctypes
from libcpp.string cimport string
from libcpp.vector cimport vector

cimport numpy as np
import numpy as np

# Mapping from C++ BMI type-name strings to numpy dtypes
DTYPE_MAP = {
    "double":           "float64",
    "float":            "float32",
    "int":              "int32",
    "long":             "int64",
    "unsigned int":     "uint32",
    "unsigned long":    "uint64",
}

# start: sft.pyx

cdef extern from "bmi_soil_freeze_thaw.hxx":
    cdef cppclass BmiSoilFreezeThaw:
        BmiSoilFreezeThaw() except +

        #  Model control functions.
        void Initialize(string config_file) except +
        void Update()
        void UpdateUntil(double time)
        void Finalize()

        #  Model information functions.
        string GetComponentName()
        int GetInputItemCount()
        int GetOutputItemCount()
        vector[string] GetInputVarNames()
        vector[string] GetOutputVarNames()

        #  Variable information functions
        int GetVarGrid(string name)
        string GetVarType(string name)
        string GetVarUnits(string name)
        int GetVarItemsize(string name)
        int GetVarNbytes(string name)
        string GetVarLocation(string name)

        double GetCurrentTime()
        double GetStartTime()
        double GetEndTime()
        string GetTimeUnits()
        double GetTimeStep()

        #  Variable getters
        void GetValue(string name, void *dest)
        void *GetValuePtr(string name)
        void GetValueAtIndices(string name, void *dest, int *inds, int count)

        #  Variable setters
        void SetValue(string name, void *src)
        void SetValueAtIndices(string name, int *inds, int count, void *src)

        #  Grid information functions
        int GetGridRank(const int grid)
        int GetGridSize(const int grid)
        string GetGridType(const int grid)

        void GetGridShape(const int grid, int *shape)
        void GetGridSpacing(const int grid, double *spacing)
        void GetGridOrigin(const int grid, double *origin)

        void GetGridX(const int grid, double *x)
        void GetGridY(const int grid, double *y)
        void GetGridZ(const int grid, double *z)

        int GetGridNodeCount(const int grid)
        int GetGridEdgeCount(const int grid)
        int GetGridFaceCount(const int grid)

        void GetGridEdgeNodes(const int grid, int *edge_nodes)
        void GetGridFaceEdges(const int grid, int *face_edges)
        void GetGridFaceNodes(const int grid, int *face_nodes)
        void GetGridNodesPerFace(const int grid, int *nodes_per_face)


cdef class SFT:
    cdef BmiSoilFreezeThaw _bmi

    METADATA = "../data/SFT"

    def __cinit__(self):
        pass

    # ------------------------------------------------------------------ #
    #  Model control                                                       #
    # ------------------------------------------------------------------ #

    def initialize(self, config_file):
        self._bmi.Initialize(config_file)

    def update(self):
        self._bmi.Update()

    def update_until(self, double time):
        self._bmi.UpdateUntil(time)

    def finalize(self):
        self._bmi.Finalize()

    # ------------------------------------------------------------------ #
    #  Model information                                                   #
    # ------------------------------------------------------------------ #

    def get_component_name(self):
        return self._bmi.GetComponentName()

    def get_input_item_count(self):
        return self._bmi.GetInputItemCount()

    def get_output_item_count(self):
        return self._bmi.GetOutputItemCount()

    def get_input_var_names(self):
        return tuple(self._bmi.GetInputVarNames())

    def get_output_var_names(self):
        return tuple(self._bmi.GetOutputVarNames())

    # ------------------------------------------------------------------ #
    #  Variable information                                                #
    # ------------------------------------------------------------------ #

    def get_var_grid(self, name):
        return self._bmi.GetVarGrid(name)

    def get_var_type(self, name):
        return self._bmi.GetVarType(name)

    def get_var_units(self, name):
        return self._bmi.GetVarUnits(name)

    def get_var_itemsize(self, name):
        return self._bmi.GetVarItemsize(name)

    def get_var_nbytes(self, name):
        return self._bmi.GetVarNbytes(name)

    def get_var_location(self, name):
        return self._bmi.GetVarLocation(name)

    # ------------------------------------------------------------------ #
    #  Time information                                                    #
    # ------------------------------------------------------------------ #

    def get_current_time(self):
        return self._bmi.GetCurrentTime()

    def get_start_time(self):
        return self._bmi.GetStartTime()

    def get_end_time(self):
        return self._bmi.GetEndTime()

    def get_time_units(self):
        return self._bmi.GetTimeUnits()

    def get_time_step(self):
        return self._bmi.GetTimeStep()

    # ------------------------------------------------------------------ #
    #  Variable getters / setters                                          #
    # ------------------------------------------------------------------ #

    def get_value(self, name, np.ndarray dest):
        """Fill *dest* (pre-allocated numpy array) with the current values."""
        self._bmi.GetValue(name, <void *>dest.data)
        return dest

    def get_value_ptr(self, name):
        """Return a numpy array view directly into the model memory (no copy)."""
        cdef void *ptr
        ptr = self._bmi.GetValuePtr(name)

        var_type  = self.get_var_type(name)
        nbytes    = self.get_var_nbytes(name)
        itemsize  = self.get_var_itemsize(name)
        count     = nbytes // itemsize if itemsize > 0 else 0
        dtype_str = DTYPE_MAP.get(var_type, "float64")

        if dtype_str == "float64":
            return np.asarray(<np.float64_t[:count]>(<np.float64_t *>ptr))
        elif dtype_str == "float32":
            return np.asarray(<np.float32_t[:count]>(<np.float32_t *>ptr))
        elif dtype_str == "int32":
            return np.asarray(<np.int32_t[:count]>(<np.int32_t *>ptr))
        elif dtype_str == "int64":
            return np.asarray(<np.int64_t[:count]>(<np.int64_t *>ptr))
        else:
            return np.frombuffer(
                (<np.uint8_t[:nbytes]>(<np.uint8_t *>ptr)).base,
                dtype=np.dtype(dtype_str)
            )

    def get_value_at_indices(self, name, np.ndarray dest,
                              np.ndarray[int, ndim=1] inds):
        cdef int count = inds.shape[0]
        self._bmi.GetValueAtIndices(name, <void *>dest.data,
                                    <int *>inds.data, count)
        return dest

    def set_value(self, name, np.ndarray src):
        """Set model variable *name* from the numpy array *src*."""
        self._bmi.SetValue(name, <void *>src.data)

    def set_value_at_indices(self, name,
                              np.ndarray[int, ndim=1] inds,
                              np.ndarray src):
        cdef int count = inds.shape[0]
        self._bmi.SetValueAtIndices(name, <int *>inds.data, count,
                                    <void *>src.data)

    # ------------------------------------------------------------------ #
    #  Grid information                                                    #
    # ------------------------------------------------------------------ #

    def get_grid_rank(self, int grid):
        return self._bmi.GetGridRank(grid)

    def get_grid_size(self, int grid):
        return self._bmi.GetGridSize(grid)

    def get_grid_type(self, int grid):
        return self._bmi.GetGridType(grid)

    def get_grid_shape(self, int grid, np.ndarray[int, ndim=1] shape):
        self._bmi.GetGridShape(grid, <int *>shape.data)
        return shape

    def get_grid_spacing(self, int grid, np.ndarray[double, ndim=1] spacing):
        self._bmi.GetGridSpacing(grid, <double *>spacing.data)
        return spacing

    def get_grid_origin(self, int grid, np.ndarray[double, ndim=1] origin):
        self._bmi.GetGridOrigin(grid, <double *>origin.data)
        return origin

    def get_grid_x(self, int grid, np.ndarray[double, ndim=1] x):
        self._bmi.GetGridX(grid, <double *>x.data)
        return x

    def get_grid_y(self, int grid, np.ndarray[double, ndim=1] y):
        self._bmi.GetGridY(grid, <double *>y.data)
        return y

    def get_grid_z(self, int grid, np.ndarray[double, ndim=1] z):
        self._bmi.GetGridZ(grid, <double *>z.data)
        return z

    def get_grid_node_count(self, int grid):
        return self._bmi.GetGridNodeCount(grid)

    def get_grid_edge_count(self, int grid):
        return self._bmi.GetGridEdgeCount(grid)

    def get_grid_face_count(self, int grid):
        return self._bmi.GetGridFaceCount(grid)

    def get_grid_edge_nodes(self, int grid,
                             np.ndarray[int, ndim=1] edge_nodes):
        self._bmi.GetGridEdgeNodes(grid, <int *>edge_nodes.data)
        return edge_nodes

    def get_grid_face_edges(self, int grid,
                             np.ndarray[int, ndim=1] face_edges):
        self._bmi.GetGridFaceEdges(grid, <int *>face_edges.data)
        return face_edges

    def get_grid_face_nodes(self, int grid,
                             np.ndarray[int, ndim=1] face_nodes):
        self._bmi.GetGridFaceNodes(grid, <int *>face_nodes.data)
        return face_nodes

    def get_grid_nodes_per_face(self, int grid,
                                 np.ndarray[int, ndim=1] nodes_per_face):
        self._bmi.GetGridNodesPerFace(grid, <int *>nodes_per_face.data)
        return nodes_per_face
