FROM mambaorg/micromamba:2.3.2

USER root

RUN for i in {1..5}; do apt-get update && break || sleep 15; done && \
    apt-get install -y --no-install-recommends \
      build-essential \
      gcc \
      g++ \
      gfortran \
      cmake \
      make \
      git \
      pkg-config \
    && rm -rf /var/lib/apt/lists/*

USER $MAMBA_USER

RUN micromamba install -y -n base -c conda-forge \
      python=3.12 \
      babelizer=0.3.9 \
      uv \
      pip \
      setuptools=69.5.1 \
      wheel \
      numpy=1.26 \
      cython=3.0.11 \
      compilers \
    && micromamba clean --all --yes

WORKDIR /workspace

RUN git clone --depth 1 \
      https://github.com/NOAA-OWP/ngen.git /workspace/ngen && \
    git clone --depth 1 \
      https://github.com/NOAA-OWP/sac-sma.git /workspace/sac-sma

# Sac-SMA needs the NextGen ISO C Fortran BMI source to build libsacbmi.so.
RUN cmake \
      -S /workspace/sac-sma \
      -B /workspace/sac-sma/cmake_build \
      -DISO_C_FORTRAN_BMI_PATH=/workspace/ngen/extern/iso_c_fortran_bmi \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON && \
    cmake --build /workspace/sac-sma/cmake_build \
      --target sacbmi \
      -j$(nproc)

ENV SAC_SMA_ROOT=/workspace/sac-sma
ENV SAC_SMA_LIB_DIR=/workspace/sac-sma/cmake_build
ENV SAC_SMA_BMI_DIR=/workspace/sac-sma/cmake_build
ENV ISO_C_FORTRAN_BMI_PATH=/workspace/ngen/extern/iso_c_fortran_bmi
ENV LD_LIBRARY_PATH=/workspace/sac-sma/cmake_build

WORKDIR /workspace
CMD ["/bin/bash"]
