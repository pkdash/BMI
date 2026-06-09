FROM mambaorg/micromamba:2.3.2

USER root

RUN apt-get update && apt-get install -y \
    build-essential \
    gfortran \
    make \
    git \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

USER $MAMBA_USER

# Install Python toolchain + HDF5/NetCDF stack all via conda-forge so
# dependency versions (HDF5 <-> NetCDF) are resolved consistently.
RUN micromamba install -y -n base -c conda-forge \
    python=3.12 \
    babelizer=0.3.9 \
    uv \
    pip \
    setuptools=69.5.1 \
    numpy \
    cython \
    wheel \
    compilers \
    hdf5 \
    libnetcdf \
    netcdf-fortran \
    && micromamba clean --all --yes

ENV NETCDF=/opt/conda
ENV LD_LIBRARY_PATH=/opt/conda/lib

USER root

WORKDIR /workspace

# ─── Clone NOAA Noah-OWP Modular ──────────────────────────────────────────────
ARG NOAH_REPO=https://github.com/NOAA-OWP/noah-owp-modular.git
ARG NOAH_REF=main
ARG BUILD_NOAH=0

RUN git clone --recurse-submodules ${NOAH_REPO} /workspace/noah-owp-modular && \
    cd /workspace/noah-owp-modular && \
    git checkout ${NOAH_REF}

RUN if [ "${BUILD_NOAH}" = "1" ]; then \
      cd /workspace/noah-owp-modular && \
      cp config/user_build_options.gfortran.linux user_build_options && \
      sed -i 's#^ COMPILERF90.*# COMPILERF90    =       gfortran#' user_build_options && \
      sed -i 's#^ NETCDFMOD.*# NETCDFMOD      =       -I/opt/conda/include#' user_build_options && \
      sed -i 's#^ NETCDFLIB.*# NETCDFLIB      =       -L/opt/conda/lib -lnetcdf -lnetcdff#' user_build_options && \
      sed -i 's#^ F90FLAGS.*# F90FLAGS       =       -g -fbacktrace -fPIC#' user_build_options && \
      make -j$(nproc) testBMI && \
      gfortran -shared -fPIC \
        -o /workspace/noah-owp-modular/libsurfacebmi.so \
        bmi/bmi.o bmi/bmi_noahowp.o src/*.o \
        -L/opt/conda/lib -lnetcdf -lnetcdff; \
    fi

ENV NOAH_LIB_DIR=/workspace/noah-owp-modular
ENV LD_LIBRARY_PATH=/workspace/noah-owp-modular:${LD_LIBRARY_PATH}

WORKDIR /workspace/user

CMD ["/bin/bash"]
