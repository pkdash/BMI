===========
pymt_snow17
===========


.. image:: https://img.shields.io/badge/CSDMS-Basic%20Model%20Interface-green.svg
        :target: https://bmi.readthedocs.io/
        :alt: Basic Model Interface

.. image:: https://img.shields.io/badge/recipe-pymt_snow17-green.svg
        :target: https://anaconda.org/conda-forge/pymt_snow17

.. image:: https://readthedocs.org/projects/pymt-snow17/badge/?version=latest
        :target: https://pymt-snow17.readthedocs.io/en/latest/?badge=latest
        :alt: Documentation Status

.. image:: https://github.com/vaishswami/pymt_snow17/actions/workflows/test.yml/badge.svg
        :target: https://github.com/vaishswami/pymt_snow17/actions/workflows/test.yml

.. image:: https://github.com/vaishswami/pymt_snow17/actions/workflows/flake8.yml/badge.svg
        :target: https://github.com/vaishswami/pymt_snow17/actions/workflows/flake8.yml

.. image:: https://github.com/vaishswami/pymt_snow17/actions/workflows/black.yml/badge.svg
        :target: https://github.com/vaishswami/pymt_snow17/actions/workflows/black.yml


Python BMI wrapper for NOAA-OWP Snow17


* Free software: Apache Software License 2.0
* Documentation: https://pymt-snow17.readthedocs.io.




========= ===================================
Component PyMT
========= ===================================
SNOW17    `from pymt.models import SNOW17`
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

----------------------
Installing pymt_snow17
----------------------



To install `pymt_snow17`,

.. code::

  conda install pymt_snow17
