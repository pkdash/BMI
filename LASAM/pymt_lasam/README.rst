==========
pymt_lasam
==========


.. image:: https://img.shields.io/badge/CSDMS-Basic%20Model%20Interface-green.svg
        :target: https://bmi.readthedocs.io/
        :alt: Basic Model Interface

.. image:: https://img.shields.io/badge/recipe-pymt_lasam-green.svg
        :target: https://anaconda.org/conda-forge/pymt_lasam

.. image:: https://readthedocs.org/projects/pymt-lasam/badge/?version=latest
        :target: https://pymt-lasam.readthedocs.io/en/latest/?badge=latest
        :alt: Documentation Status

.. image:: https://github.com/vaishaliswaminathan/pymt_lasam/actions/workflows/test.yml/badge.svg
        :target: https://github.com/vaishaliswaminathan/pymt_lasam/actions/workflows/test.yml

.. image:: https://github.com/vaishaliswaminathan/pymt_lasam/actions/workflows/flake8.yml/badge.svg
        :target: https://github.com/vaishaliswaminathan/pymt_lasam/actions/workflows/flake8.yml

.. image:: https://github.com/vaishaliswaminathan/pymt_lasam/actions/workflows/black.yml/badge.svg
        :target: https://github.com/vaishaliswaminathan/pymt_lasam/actions/workflows/black.yml


Python BMI wrapper for LASAM/CASAM (LGAR-C)


* Free software: Apache Software License 2.0
* Documentation: https://pymt-lasam.readthedocs.io.




========= ===================================
Component PyMT
========= ===================================
LASAM     `from pymt.models import LASAM`
========= ===================================

---------------
Installing pymt
---------------

Installing `pymt` from the `conda-forge` channel can be achieved by adding
`conda-forge` to your channels with:

.. code::

  conda config --add channels conda-forge

*Note*: Before installing `pymt`, you may want to create a separate environment
into which to install it. This can be done with,

.. code::

  conda create -n pymt python=3
  conda activate pymt

Once the `conda-forge` channel has been enabled, `pymt` can be installed with:

.. code::

  conda install pymt

It is possible to list all of the versions of `pymt` available on your platform with:

.. code::

  conda search pymt --channel conda-forge

---------------------
Installing pymt_lasam
---------------------



To install `pymt_lasam`,

.. code::

  conda install pymt_lasam
