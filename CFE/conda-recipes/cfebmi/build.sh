#!/usr/bin/env bash
set -euo pipefail

# Build CFE BMI shared library for conda packaging.
# We use -DNGEN=ON because that target builds libcfebmi.so.

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DNGEN=ON

cmake --build build --parallel "${CPU_COUNT:-2}"

# Install directories
mkdir -p "${PREFIX}/lib"
mkdir -p "${PREFIX}/include/bmi"
mkdir -p "${PREFIX}/include/cfe"
mkdir -p "${PREFIX}/lib/pkgconfig"

# Install the shared library
cp build/libcfebmi.so* "${PREFIX}/lib/"

# Install headers needed by downstream packages (e.g., pymt_cfe)
cp include/bmi.h "${PREFIX}/include/bmi/"
cp include/*.h "${PREFIX}/include/cfe/"

# Write a corrected pkg-config file.
# The upstream cfebmi.pc.in in v2.0.1 has an incorrect Libs line (-lmylib),
# so we generate a corrected version here.
cat > "${PREFIX}/lib/pkgconfig/cfebmi.pc" <<EOF
prefix=${PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: cfebmi
Description: OWP CFE BMI Module Shared Library
Version: 2.0.1
Libs: -L\${libdir} -lcfebmi
Cflags: -I\${includedir}/bmi -I\${includedir}/cfe
EOF
