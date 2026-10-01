#! /usr/bin/env python
import os
import shlex
import subprocess
import sys
from pathlib import Path

import numpy as np
from setuptools import Extension, find_packages, setup

try:
    from Cython.Build import cythonize
except ImportError:
    cythonize = None


def _unique_existing(paths):
    seen = set()
    out = []
    for p in paths:
        if not p:
            continue
        p = str(Path(p))
        if p not in seen and Path(p).exists():
            seen.add(p)
            out.append(p)
    return out


def _pkg_config_dirs(package_name="smpbmi"):
    include_dirs = []
    library_dirs = []
    try:
        cflags = subprocess.check_output(
            ["pkg-config", "--cflags", package_name],
            text=True, stderr=subprocess.DEVNULL,
        ).strip()
        for token in shlex.split(cflags):
            if token.startswith("-I") and len(token) > 2:
                include_dirs.append(token[2:])
    except Exception:
        pass
    try:
        lflags = subprocess.check_output(
            ["pkg-config", "--libs-only-L", package_name],
            text=True, stderr=subprocess.DEVNULL,
        ).strip()
        for token in shlex.split(lflags):
            if token.startswith("-L") and len(token) > 2:
                library_dirs.append(token[2:])
    except Exception:
        pass
    return include_dirs, library_dirs


def _discover_smp_paths():
    env = os.environ
    smp_root = env.get("SMP_ROOT", "")
    conda_prefix = env.get("CONDA_PREFIX", "")

    pkg_inc, pkg_lib = _pkg_config_dirs("smpbmi")

    include_candidates = [
        env.get("SMP_INCLUDE_DIR", ""),
        env.get("SMP_BMI_DIR", ""),
        os.path.join(sys.prefix, "include"),
        os.path.join(conda_prefix, "include") if conda_prefix else "",
        os.path.join(smp_root, "include") if smp_root else "",
        os.path.join(smp_root, "bmi") if smp_root else "",
        os.path.join(smp_root, "src") if smp_root else "",
        "/workspace/smp/include",
        "/workspace/smp/bmi",
        "/workspace/smp/src",
    ] + pkg_inc

    library_candidates = [
        env.get("SMP_LIB_DIR", ""),
        os.path.join(sys.prefix, "lib"),
        os.path.join(conda_prefix, "lib") if conda_prefix else "",
        os.path.join(smp_root, "build") if smp_root else "",
        os.path.join(smp_root, "lib") if smp_root else "",
        "/workspace/smp/build",
        "/workspace/smp/lib",
    ] + pkg_lib

    return _unique_existing(include_candidates), _unique_existing(library_candidates)


include_dirs, library_dirs = _discover_smp_paths()

runtime_library_dirs = []
for d in [os.environ.get("SMP_RPATH", ""), os.environ.get("SMP_LIB_DIR", "")]:
    if d and Path(d).exists() and d not in runtime_library_dirs:
        runtime_library_dirs.append(d)

common_flags = {
    "include_dirs": [np.get_include(), *include_dirs],
    "library_dirs": library_dirs,
    "runtime_library_dirs": runtime_library_dirs,
    "define_macros": [("BMI_ACTIVE", None), ("NGEN", None)],
    "undef_macros": [],
    "extra_compile_args": ["-std=c++14"],
    "language": "c++",
}

if sys.platform.startswith("win"):
    common_flags["include_dirs"].append(os.path.join(sys.prefix, "Library", "include"))
    common_flags["library_dirs"].append(os.path.join(sys.prefix, "Library", "lib"))


def _extension_source():
    pyx_source = Path("pymt_smp/lib/smp.pyx")
    cpp_source = Path("pymt_smp/lib/smp.cpp")
    if cythonize is not None and pyx_source.exists():
        return str(pyx_source)
    if cpp_source.exists():
        return str(cpp_source)
    raise RuntimeError(
        "Cannot build pymt_smp: missing pymt_smp/lib/smp.cpp and Cython is "
        "not available to generate it from pymt_smp/lib/smp.pyx."
    )


ext_modules = [
    Extension(
        "pymt_smp.lib.smp",
        sources=[_extension_source()],
        libraries=["smpbmi"],
        **common_flags,
    ),
]

if cythonize is not None and ext_modules[0].sources[0].endswith(".pyx"):
    ext_modules = cythonize(ext_modules, language_level=3)

entry_points = {
    "pymt.plugins": [
        "SMP=pymt_smp.bmi:SMP",
    ]
}


def read(filename):
    with open(filename, "r", encoding="utf-8") as fp:
        return fp.read()


long_description = "\n\n".join(
    [read("README.rst"), read("CREDITS.rst"), read("CHANGES.rst")]
)

setup(
    name="pymt_smp",
    author="Vaishali Swaminathan",
    author_email="",
    description="PyMT plugin for NOAA-OWP Soil Moisture Profiles",
    long_description=long_description,
    version="0.1",
    url="https://github.com/NOAA-OWP/SoilMoistureProfiles",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Science/Research",
        "License :: OSI Approved :: MIT License",
        "Operating System :: POSIX :: Linux",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.11",
    ],
    keywords=["bmi", "pymt", "soil moisture profiles", "NextGen"],
    install_requires=open("requirements.txt", "r").read().splitlines(),
    setup_requires=["cython"],
    ext_modules=ext_modules,
    packages=find_packages(),
    entry_points=entry_points,
    include_package_data=True,
)
