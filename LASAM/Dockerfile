FROM mambaorg/micromamba:2.3.2
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    g++ \
    cmake \
    git \
    pkg-config \
 && rm -rf /var/lib/apt/lists/*
USER $MAMBA_USER
RUN micromamba install -y -n base -c conda-forge python=3.12 babelizer=0.3.9 uv pip setuptools=69.5.1 numpy=1.26 cython=3.0.11 wheel compilers && micromamba clean --all --yes
WORKDIR /workspace
RUN git clone --depth 1 https://github.com/NOAA-OWP/LGAR-C.git /workspace/LGAR-C
WORKDIR /workspace/LGAR-C
RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_VISIBILITY_PRESET=default -DCMAKE_VISIBILITY_INLINES_HIDDEN=OFF && cmake --build build --target lasambmi -j$(nproc)
ENV LASAM_ROOT=/workspace/LGAR-C
ENV LASAM_INCLUDE_DIR=/workspace/LGAR-C/include
ENV LASAM_LIB_DIR=/workspace/LGAR-C/build
ENV LD_LIBRARY_PATH=/workspace/LGAR-C/build
WORKDIR /workspace
CMD ["/bin/bash"]
