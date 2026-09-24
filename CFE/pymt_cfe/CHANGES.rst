Changelog for pymt_cfe
======================

0.2.0 (2026-09-23)
------------------

- Embed the discovered CFE library directories in the extension as an RPATH, so
  ``import pymt_cfe`` resolves ``libcfebmi`` without the caller having to export
  ``LD_LIBRARY_PATH``. The conda ``activate.d`` hook ``install.sh`` used to write
  for that purpose is no longer needed and has been removed.
- Pin the build-time numpy to ``<2``. The extension is imported alongside
  consumers pinned to numpy 1.x -- notably NOAA-OWP/ngen, which rejects
  numpy>=2.0.0 at configure time -- so it is built against the same major
  version. ``install.sh`` applies the same constraint directly, since
  ``--no-build-isolation`` bypasses ``[build-system] requires``; it installs
  ``numpy<2`` when numpy is absent, and warns rather than downgrading an
  environment that already has numpy 2.
- ``install.sh`` now installs into a virtualenv as well as a conda environment,
  resolving the interpreter from ``--python``, ``$VIRTUAL_ENV`` or
  ``$CONDA_PREFIX``. It also gains a ``--source-tree`` mode that installs from a
  checkout without building an sdist first, and ``--help``.
- Fix a crash in ``install.sh`` under the bash 3.2 that ships with macOS, which
  has no ``mapfile`` builtin.
- Fix the project url, which pointed at a ``pkdash/pymt_cfe`` repository that
  does not exist. It now names the monorepo, with ``project_urls["Source"]``
  giving the subdirectory.

0.1.0 (2026-06-26)
------------------

- Initial release

