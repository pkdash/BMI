=============
pymt_noah_owp
=============


.. image:: https://img.shields.io/badge/CSDMS-Basic%20Model%20Interface-green.svg
        :target: https://bmi.readthedocs.io/
        :alt: Basic Model Interface

.. image:: https://img.shields.io/badge/recipe-pymt_noah_owp-green.svg
        :target: https://anaconda.org/conda-forge/pymt_noah_owp

.. image:: https://readthedocs.org/projects/pymt-noah-owp/badge/?version=latest
        :target: https://pymt-noah-owp.readthedocs.io/en/latest/?badge=latest
        :alt: Documentation Status

.. image:: https://github.com/pkdash/pymt_noah_owp/actions/workflows/test.yml/badge.svg
        :target: https://github.com/pkdash/pymt_noah_owp/actions/workflows/test.yml

.. image:: https://github.com/pkdash/pymt_noah_owp/actions/workflows/flake8.yml/badge.svg
        :target: https://github.com/pkdash/pymt_noah_owp/actions/workflows/flake8.yml

.. image:: https://github.com/pkdash/pymt_noah_owp/actions/workflows/black.yml/badge.svg
        :target: https://github.com/pkdash/pymt_noah_owp/actions/workflows/black.yml


Python BMI wrapper for NOAA-OWP Noah Modular


* Free software: MIT License
* Documentation: https://pymt-noah-owp.readthedocs.io.




========= ===================================
Component PyMT
========= ===================================
NOAH_OWP  `from pymt.models import NOAH_OWP`
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

------------------------
Installing pymt_noah_owp
------------------------



To install `pymt_noah_owp`,

.. code::

  conda install pymt_noah_owp
