FROM mambaorg/micromamba:2.3.2

USER root

RUN for i in {1..5}; do apt-get update && break || sleep 15; done && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    g++ \
    cmake \
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
    numpy=1.26.4 \
    cython=3.0.11 \
    wheel \
    compilers \
    && micromamba clean --all --yes

WORKDIR /workspace

RUN git clone --recurse-submodules https://github.com/NOAA-OWP/SoilMoistureProfiles.git smp

WORKDIR /workspace/smp

RUN cmake -S . -B build \
      -DNGEN=ON \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CXX_VISIBILITY_PRESET=default \
      -DCMAKE_VISIBILITY_INLINES_HIDDEN=OFF && \
    cmake --build build -j$(nproc) && \
    ls -lh /workspace/smp/build/libsmpbmi.so*

ENV SMP_ROOT=/workspace/smp
ENV SMP_LIB_DIR=/workspace/smp/build
ENV SMP_INCLUDE_DIR=/workspace/smp/include
ENV LD_LIBRARY_PATH=/workspace/smp/build

WORKDIR /workspace

CMD ["/bin/bash"]
