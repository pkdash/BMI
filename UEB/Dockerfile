FROM mambaorg/micromamba:2.3.2

USER root

RUN for i in {1..5}; do apt-get update && break || sleep 15; done && \
    apt-get install -y --no-install-recommends \
      build-essential \
      g++ \
      cmake \
      git \
      pkg-config \
      libboost-serialization-dev \
      libnetcdf-dev \
      netcdf-bin \
    && rm -rf /var/lib/apt/lists/*

USER $MAMBA_USER

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
    && micromamba clean --all --yes

WORKDIR /workspace

# UEB expects bmi-cxx as a sibling directory when BMICXX_INCLUDE_DIRS is not set.
RUN git clone --depth 1 https://github.com/csdms/bmi-cxx.git /workspace/bmi-cxx

RUN git clone --depth 1 --branch development \
      https://github.com/NGWPC/ueb_bmi.git /workspace/ueb_bmi

WORKDIR /workspace/ueb_bmi

# USE_EWTS is ON by default in the current UEB repository. Disable it for a
# self-contained wrapper image unless nwm-ewts is deliberately installed.
RUN cmake -S . -B cmake_build \
      -DBMICXX_INCLUDE_DIRS=/workspace/bmi-cxx \
      -DUSE_EWTS=OFF \
      -DUEB_SUPPRESS_OUTPUTS=ON \
      -DCMAKE_BUILD_TYPE=Release && \
    cmake --build cmake_build -j$(nproc)

ENV UEB_ROOT=/workspace/ueb_bmi
ENV UEB_INCLUDE_DIR=/workspace/ueb_bmi/src/bmi
ENV UEB_LIB_DIR=/workspace/ueb_bmi/cmake_build/src
ENV LD_LIBRARY_PATH=/workspace/ueb_bmi/cmake_build/src

WORKDIR /workspace
CMD ["/bin/bash"]
