FROM mambaorg/micromamba:2.3.2

USER root

RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    g++ \
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
    numpy \
    cython \
    wheel \
    compilers \
    cmake \
    make \
    libboost-devel \
    && micromamba clean --all --yes

WORKDIR /workspace

# Clone TOPMODEL
RUN git clone --recurse-submodules https://github.com/NOAA-OWP/topmodel.git

WORKDIR /workspace/topmodel

# Build the TOPMODEL BMI shared library with CMake.
# Upstream NOAA-OWP/topmodel is a CMake project (there is no Makefile), and the BMI
# library now also compiles src/bmi_serialization.cpp (C++17) and links Boost::serialization.
# Activate the conda env so CMake finds conda-forge's Boost (>= 1.86) and compilers.
ARG MAMBA_DOCKERFILE_ACTIVATE=1
RUN cmake -B build -S . \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH="$CONDA_PREFIX" \
      -DTESTS_WITH_ASAN=OFF && \
    cmake --build build -j"$(nproc)" --target topmodelbmi && \
    ls -lh /workspace/topmodel/build/libtopmodelbmi.so*

ENV LD_LIBRARY_PATH=/workspace/topmodel/build:/workspace/topmodel/src

# NOTE:
# The PyMT TOPMODEL wrapper is generated at runtime from a mounted host directory,
# so we intentionally do not COPY or install pymt_topmodel during image build.
WORKDIR /workspace

CMD ["/bin/bash"]