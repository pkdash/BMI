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


def _pkg_config_dirs(package_name="sftbmi"):
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


def _discover_sft_paths():
    env = os.environ
    sft_root     = env.get("SFT_ROOT", "")
    conda_prefix = env.get("CONDA_PREFIX", "")

    pkg_inc, pkg_lib = _pkg_config_dirs("sftbmi")

    include_candidates = [
        env.get("SFT_INCLUDE_DIR", ""),
        env.get("SFT_BMI_DIR", ""),
        os.path.join(sys.prefix, "include"),
        os.path.join(conda_prefix, "include") if conda_prefix else "",
        os.path.join(sft_root, "include") if sft_root else "",
        os.path.join(sft_root, "bmi")     if sft_root else "",
        os.path.join(sft_root, "src")     if sft_root else "",
        "/workspace/sft/include",
        "/workspace/sft/bmi",
        "/workspace/sft/src",
    ] + pkg_inc

    library_candidates = [
        env.get("SFT_LIB_DIR", ""),
        os.path.join(sys.prefix, "lib"),
        os.path.join(conda_prefix, "lib") if conda_prefix else "",
        os.path.join(sft_root, "build") if sft_root else "",
        os.path.join(sft_root, "lib")   if sft_root else "",
        "/workspace/sft/build",
        "/workspace/sft/lib",
    ] + pkg_lib

    return (
        _unique_existing(include_candidates),
        _unique_existing(library_candidates),
    )


include_dirs, library_dirs = _discover_sft_paths()

# ── Runtime-library path (rpath) ─────────────────────────────────────────────
# Embed the path to libsftbmi.so directly in the extension .so so that it is
# found at import time even before LD_LIBRARY_PATH is exported.  SFT_RPATH is
# set by install.sh; fall back to SFT_LIB_DIR if it is not present.
_sft_rpath = os.environ.get("SFT_RPATH") or os.environ.get("SFT_LIB_DIR", "")

extra_link_args: list[str] = []
if not sys.platform.startswith("win"):
    if _sft_rpath:
        extra_link_args.append(f"-Wl,-rpath,{_sft_rpath}")
    if sys.platform.startswith("linux"):
        # Fail at *build* time (not silently at import time) if any symbol
        # from libsftbmi.so is missing — catches hidden-vtable builds early.
        extra_link_args.append("-Wl,-z,defs")

common_flags = {
    "include_dirs": [np.get_include(), *include_dirs],
    "library_dirs": library_dirs,
    "define_macros": [("BMI_ACTIVE", None)],  # matches SFT CMakeLists
    "undef_macros": [],
    "extra_compile_args": ["-std=c++14"],
    "extra_link_args": extra_link_args,
    "language": "c++",
}

if sys.platform.startswith("win"):
    common_flags["include_dirs"].append(
        os.path.join(sys.prefix, "Library", "include")
    )
    common_flags["library_dirs"].append(
        os.path.join(sys.prefix, "Library", "lib")
    )


def _extension_source():
    pyx_source = Path("pymt_sft/lib/sft.pyx")
    cpp_source = Path("pymt_sft/lib/sft.cpp")
    if cythonize is not None and pyx_source.exists():
        return str(pyx_source)
    if cpp_source.exists():
        return str(cpp_source)
    raise RuntimeError(
        "Cannot build pymt_sft: missing pymt_sft/lib/sft.cpp and Cython is "
        "not available to generate it from pymt_sft/lib/sft.pyx."
    )


ext_modules = [
    Extension(
        "pymt_sft.lib.sft",
        sources=[_extension_source()],
        libraries=["sftbmi"],
        **common_flags,
    ),
]

if cythonize is not None and ext_modules[0].sources[0].endswith(".pyx"):
    ext_modules = cythonize(ext_modules, language_level=3)

entry_points = {
    "pymt.plugins": [
        "SFT=pymt_sft.bmi:SFT",
    ]
}


def read(filename):
    with open(filename, "r", encoding="utf-8") as fp:
        return fp.read()


long_description = "\n\n".join(
    [read("README.rst"), read("CREDITS.rst"), read("CHANGES.rst")]
)

setup(
    name="pymt_sft",
    author="Pabitra Dash",
    author_email="pkdash_reena@hotmail.com",
    description="PyMT plugin for pymt_sft",
    long_description=long_description,
    version="0.1",
    url="https://github.com/pkdash/BMI",
    project_urls={
        "Source": "https://github.com/pkdash/BMI/tree/main/SOIL-FREEZE-THAW/pymt_sft",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Science/Research",
        "License :: OSI Approved :: MIT License",
        "Operating System :: POSIX :: Linux",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.11",
    ],
    keywords=["bmi", "pymt"],
    install_requires=open("requirements.txt", "r").read().splitlines(),
    setup_requires=["cython"],
    ext_modules=ext_modules,
    packages=find_packages(),
    entry_points=entry_points,
    include_package_data=True,
)
