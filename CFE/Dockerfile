FROM mambaorg/micromamba:2.3.2

USER root

RUN apt-get update && apt-get install -y \
    build-essential \
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
    numpy \
    cython \
    wheel \
    compilers \
    && micromamba clean --all --yes

WORKDIR /workspace

# Clone CFE
RUN git clone --recurse-submodules https://github.com/NOAA-OWP/cfe.git

WORKDIR /workspace/cfe

# Build CFE for ngen/BMI
RUN cmake -S . -B build -DNGEN=ON && \
    cmake --build build -j$(nproc)

ENV LD_LIBRARY_PATH=/workspace/cfe/build

# NOTE:
# The PyMT CFE wrapper is generated at runtime from a mounted host directory,
# so we intentionally do not COPY or install pymt_cfe during image build.
WORKDIR /workspace

CMD ["/bin/bash"]