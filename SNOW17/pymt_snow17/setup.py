#! /usr/bin/env python
import contextlib, os, shutil, subprocess, sys
from pathlib import Path
import numpy as np
from setuptools import Extension, find_packages, setup
from setuptools.command.build_ext import build_ext as _build_ext

def _unique_existing(paths):
    seen=set(); out=[]
    for p in paths:
        if not p: continue
        p=str(Path(p))
        if p not in seen and Path(p).exists():
            seen.add(p); out.append(p)
    return out

def _discover_snow17_paths():
    env=os.environ
    snow_root=env.get("SNOW17_ROOT","")
    lib_dir=env.get("SNOW17_LIB_DIR","")
    bmi_dir=env.get("SNOW17_BMI_DIR","")
    mod_dir=env.get("SNOW17_MOD_DIR","")
    include_candidates=[
        env.get("SNOW17_INCLUDE_DIR",""), bmi_dir, mod_dir, lib_dir,
        os.path.join(lib_dir,"iso_c_bmi") if lib_dir else "",
        os.path.join(sys.prefix,"include"),
        os.path.join(snow_root,"src","bmi") if snow_root else "",
        os.path.join(snow_root,"src","share") if snow_root else "",
        os.path.join(snow_root,"src","driver") if snow_root else "",
        os.path.join(snow_root,"src","snow19") if snow_root else "",
        os.path.join(snow_root,"cmake_build") if snow_root else "",
        os.path.join(snow_root,"cmake_build","iso_c_bmi") if snow_root else "",
        "/workspace/snow17/cmake_build", "/workspace/snow17/cmake_build/iso_c_bmi",
        "/workspace/snow17/src/bmi", "/workspace/snow17/src/share",
        "/workspace/snow17/src/driver", "/workspace/snow17/src/snow19"]
    library_candidates=[lib_dir, os.path.join(sys.prefix,"lib"), os.path.join(snow_root,"cmake_build") if snow_root else "", "/workspace/snow17/cmake_build"]
    return _unique_existing(include_candidates), _unique_existing(library_candidates)

def _find_fortran_compiler():
    for c in [os.environ.get("FC","").strip(), "gfortran", "ifort", "flang", "nvfortran", "f95", "f90"]:
        if c and shutil.which(c): return shutil.which(c)
    raise RuntimeError("No Fortran compiler found. Set FC or install gfortran.")

include_dirs, library_dirs = _discover_snow17_paths()
common_flags={"include_dirs":[np.get_include(), *include_dirs], "library_dirs":library_dirs, "define_macros":[], "undef_macros":[], "extra_compile_args":[], "language":"c"}
ext_modules=[Extension("pymt_snow17.lib.snow17", ["pymt_snow17/lib/snow17.pyx"], libraries=["snow17bmi"], extra_objects=["pymt_snow17/lib/bmi_interoperability.o"], **common_flags)]
entry_points={"pymt.plugins":["SNOW17=pymt_snow17.bmi:SNOW17"]}

@contextlib.contextmanager
def as_cwd(path):
    prev=os.getcwd(); os.chdir(path)
    try: yield
    finally: os.chdir(prev)

def build_interoperability():
    cmd=[_find_fortran_compiler(), "-c"]
    if not sys.platform.startswith("win"): cmd.append("-fPIC")
    for include_dir in common_flags["include_dirs"]: cmd.append(f"-I{include_dir}")
    cmd.append("bmi_interoperability.f90")
    subprocess.check_call(cmd)

class build_ext(_build_ext):
    def run(self):
        with as_cwd("pymt_snow17/lib"):
            build_interoperability()
        _build_ext.run(self)

def read(filename):
    with open(filename,"r",encoding="utf-8") as fp: return fp.read()
long_description="\n\n".join([read("README.rst"), read("CREDITS.rst"), read("CHANGES.rst")])
setup(name="pymt_snow17", author="Vaishali Swaminathan", author_email="", description="PyMT plugin for NOAA-OWP Snow17", long_description=long_description, version="0.1", url="https://github.com/NOAA-OWP/snow17", project_urls={"Source": "https://github.com/pkdash/BMI/tree/main/SNOW17/pymt_snow17"}, classifiers=["Development Status :: 4 - Beta", "Intended Audience :: Science/Research", "License :: OSI Approved :: Apache Software License", "Operating System :: POSIX :: Linux", "Programming Language :: Python :: 3 :: Only"], keywords=["bmi","pymt","snow17","ngen"], install_requires=open("requirements.txt","r").read().splitlines(), setup_requires=["cython"], ext_modules=ext_modules, cmdclass=dict(build_ext=build_ext), packages=find_packages(), entry_points=entry_points, include_package_data=True)
