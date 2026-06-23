FROM mambaorg/micromamba:2.3.2

USER root

# TODO: Document why we need to retry apt-get update (e.g., network issues, etc.)
RUN for i in {1..5}; do apt-get update && break || sleep 15; done && apt-get install -y --no-install-recommends \
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

# Clone SFT — no submodules needed for the NGEN (shared-library) build;
# SoilMoistureProfiles is only required for the PFRAMEWORK standalone target.
RUN git clone https://github.com/NOAA-OWP/SoilFreezeThaw.git sft

WORKDIR /workspace/sft

# -DNGEN=ON builds libsftbmi.so (the BMI shared library).
# CMakeLists also sets -DBMI_ACTIVE via add_compile_definitions.
RUN cmake -S . -B build -DNGEN=ON && \
    cmake --build build -j$(nproc)

ENV LD_LIBRARY_PATH=/workspace/sft/build

# NOTE:
# The PyMT SFT wrapper is generated at runtime from a mounted host directory,
# so we intentionally do not COPY or install pymt_sft during image build.
WORKDIR /workspace

CMD ["/bin/bash"]
