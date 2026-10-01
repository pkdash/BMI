#!/usr/bin/env python
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


def unique_existing(paths):
    result, seen = [], set()
    for path in paths:
        if not path:
            continue
        path = str(Path(path).expanduser())
        if path not in seen and Path(path).exists():
            seen.add(path)
            result.append(path)
    return result


def pkg_config_dirs(package_names=("uebcxx", "bmiuebcxx")):
    includes, libraries = [], []
    for package in package_names:
        try:
            out = subprocess.check_output(
                ["pkg-config", "--cflags", package],
                text=True, stderr=subprocess.DEVNULL
            )
            includes.extend(
                token[2:] for token in shlex.split(out)
                if token.startswith("-I") and len(token) > 2
            )
        except Exception:
            pass
        try:
            out = subprocess.check_output(
                ["pkg-config", "--libs-only-L", package],
                text=True, stderr=subprocess.DEVNULL
            )
            libraries.extend(
                token[2:] for token in shlex.split(out)
                if token.startswith("-L") and len(token) > 2
            )
        except Exception:
            pass
    return includes, libraries


def discover_ueb_paths():
    env = os.environ
    root = env.get("UEB_ROOT", "")
    conda = env.get("CONDA_PREFIX", "")
    pkg_inc, pkg_lib = pkg_config_dirs()

    include_candidates = [
        env.get("UEB_INCLUDE_DIR", ""),
        env.get("BMICXX_INCLUDE_DIRS", ""),
        f"{root}/src/bmi" if root else "",
        f"{root}/src/ueb" if root else "",
        f"{root}/src/utilities" if root else "",
        f"{Path(root).parent}/bmi-cxx" if root else "",
        "/workspace/ueb_bmi/src/bmi",
        "/workspace/ueb_bmi/src/ueb",
        "/workspace/ueb_bmi/src/utilities",
        "/workspace/bmi-cxx",
        f"{sys.prefix}/include",
        f"{conda}/include" if conda else "",
    ] + pkg_inc

    library_candidates = [
        env.get("UEB_LIB_DIR", ""),
        f"{root}/cmake_build/src" if root else "",
        f"{root}/build/src" if root else "",
        f"{root}/cmake_build" if root else "",
        "/workspace/ueb_bmi/cmake_build/src",
        f"{sys.prefix}/lib",
        f"{conda}/lib" if conda else "",
    ] + pkg_lib

    return unique_existing(include_candidates), unique_existing(library_candidates)


include_dirs, library_dirs = discover_ueb_paths()
rpath = os.environ.get("UEB_RPATH") or os.environ.get("UEB_LIB_DIR")

pyx = Path("pymt_ueb/lib/ueb.pyx")
cpp = Path("pymt_ueb/lib/ueb.cpp")
if cythonize is not None and pyx.exists():
    source = str(pyx)
elif cpp.exists():
    source = str(cpp)
else:
    raise RuntimeError("Missing pymt_ueb/lib/ueb.pyx and generated ueb.cpp")

extension_kwargs = dict(
    sources=[source],
    include_dirs=[np.get_include(), *include_dirs],
    library_dirs=library_dirs,
    libraries=["bmiuebcxx", "netcdf", "boost_serialization"],
    language="c++",
    extra_compile_args=["-std=c++17"],
)
if rpath and Path(rpath).exists() and sys.platform.startswith("linux"):
    extension_kwargs["runtime_library_dirs"] = [rpath]

ext_modules = [Extension("pymt_ueb.lib.ueb", **extension_kwargs)]
if cythonize is not None and source.endswith(".pyx"):
    ext_modules = cythonize(ext_modules, language_level=3)

setup(
    name="pymt_ueb",
    version="0.1.0",
    author="Vaishali Swaminathan",
    author_email="vaishaliswaminathan@tamu.edu",
    description="PyMT plugin for the UEB snow model",
    url="https://github.com/NGWPC/ueb_bmi",
    license="MIT",
    packages=find_packages(),
    include_package_data=True,
    install_requires=["numpy"],
    setup_requires=["cython"],
    ext_modules=ext_modules,
    entry_points={"pymt.plugins": ["UEB=pymt_ueb.bmi:UEB"]},
    python_requires=">=3.10",
)
