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
    && micromamba clean --all --yes

WORKDIR /workspace

# Clone TOPMODEL
RUN git clone --recurse-submodules https://github.com/NOAA-OWP/topmodel.git

WORKDIR /workspace/topmodel/src

# Build TOPMODEL using its Makefile
RUN make clean && make

# Build shared TOPMODEL BMI library for Babelizer/PyMT
RUN mkdir -p /workspace/topmodel/build && \
    gcc -fPIC -shared \
      -I/workspace/topmodel/include \
      -I/workspace/topmodel/src \
      /workspace/topmodel/src/bmi_topmodel.c \
      /workspace/topmodel/src/topmodel.c \
      -o /workspace/topmodel/build/libtopmodelbmi.so && \
    ls -lh /workspace/topmodel/build/libtopmodelbmi.so

ENV LD_LIBRARY_PATH=/workspace/topmodel/build:/workspace/topmodel/src

# NOTE:
# The PyMT TOPMODEL wrapper is generated at runtime from a mounted host directory,
# so we intentionally do not COPY or install pymt_topmodel during image build.
WORKDIR /workspace

CMD ["/bin/bash"]