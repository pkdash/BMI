FROM mambaorg/micromamba:2.3.2

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ gfortran cmake make git pkg-config \
    && rm -rf /var/lib/apt/lists/*

USER $MAMBA_USER
RUN micromamba install -y -n base -c conda-forge \
    python=3.12 babelizer=0.3.9 uv pip setuptools=69.5.1 \
    numpy cython wheel compilers \
    && micromamba clean --all --yes

USER root
WORKDIR /workspace
RUN git clone --recurse-submodules https://github.com/NOAA-OWP/snow17.git /workspace/snow17 && \
    git clone --recurse-submodules https://github.com/NOAA-OWP/iso_c_fortran_bmi.git /workspace/iso_c_fortran_bmi

WORKDIR /workspace/snow17
RUN cmake -B cmake_build -S . \
      -DCMAKE_BUILD_TYPE=Release \
      -DISO_C_FORTRAN_BMI_PATH=/workspace/iso_c_fortran_bmi && \
    cmake --build cmake_build --target snow17bmi -j$(nproc) && \
    find cmake_build -name "*.so*" -print

ENV SNOW17_ROOT=/workspace/snow17
ENV SNOW17_LIB_DIR=/workspace/snow17/cmake_build
ENV SNOW17_BMI_DIR=/workspace/snow17/cmake_build
ENV SNOW17_MOD_DIR=/workspace/snow17/cmake_build/iso_c_bmi
ENV LD_LIBRARY_PATH=/workspace/snow17/cmake_build:/workspace/snow17/cmake_build/iso_c_bmi

WORKDIR /workspace/user
CMD ["/bin/bash"]
