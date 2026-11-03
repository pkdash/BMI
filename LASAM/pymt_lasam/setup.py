import os, sys
from pathlib import Path
import numpy as np
from setuptools import Extension, find_packages, setup
try:
    from Cython.Build import cythonize
except ImportError:
    cythonize = None

def existing(items):
    out=[]
    for p in items:
        if p and Path(p).exists() and p not in out: out.append(p)
    return out
root=os.environ.get("LASAM_ROOT", "")
include_dirs=existing([os.environ.get("LASAM_INCLUDE_DIR", ""), os.environ.get("LASAM_BMI_DIR", ""), f"{root}/include" if root else "", f"{root}/bmi" if root else "", f"{root}/giuh" if root else "", "/workspace/LGAR-C/include", "/workspace/LGAR-C/bmi", "/workspace/LGAR-C/giuh", f"{sys.prefix}/include"])
library_dirs=existing([os.environ.get("LASAM_LIB_DIR", ""), f"{root}/build" if root else "", f"{root}/cmake_build" if root else "", "/workspace/LGAR-C/build", f"{sys.prefix}/lib"])
pyx=Path("pymt_lasam/lib/lasam.pyx"); cpp=Path("pymt_lasam/lib/lasam.cpp")
source=str(pyx if cythonize is not None and pyx.exists() else cpp)
kwargs=dict(sources=[source], include_dirs=[np.get_include(), *include_dirs], library_dirs=library_dirs, libraries=["lasambmi", "m"], language="c++", extra_compile_args=["-std=c++14"])
rpath=os.environ.get("LASAM_RPATH") or os.environ.get("LASAM_LIB_DIR")
if rpath and Path(rpath).exists() and sys.platform.startswith("linux"): kwargs["runtime_library_dirs"]=[rpath]
ext=[Extension("pymt_lasam.lib.lasam", **kwargs)]
if cythonize is not None and source.endswith(".pyx"): ext=cythonize(ext, language_level=3)
setup(name="pymt_lasam", version="0.1.0", author="Vaishali Swaminathan", author_email="vaishaliswaminathan@tamu.edu", description="PyMT plugin for LASAM/CASAM", url="https://github.com/NOAA-OWP/LGAR-C", license="Apache-2.0", packages=find_packages(), include_package_data=True, install_requires=["numpy"], ext_modules=ext, entry_points={"pymt.plugins":["LASAM=pymt_lasam.bmi:LASAM"]}, python_requires=">=3.10")
