# BMI Model Wrappers

This repository hosts Python BMI wrapper projects for BIM compatible hydrological models written in C, C++, or Fortran.

## Purpose

The goal of this project is to:

- Develop and maintain Python-accessible BMI interfaces for multiple models
- Keep each model wrapper isolated in its own folder (build config, package, scripts)
- Standardize build, test, and packaging workflows across models
- Support reproducible local and container-based development

## Current Status

- `CFE/` contains the existing CFE BMI wrapper workflow and packaging setup.
- Additional model wrappers (for example, NOAH-OWP) will be added as separate sibling folders.

## Planned Structure

Each model wrapper will follow a similar pattern:

- model-specific `babel.toml`
- Python package source (`pymt_<model>`)
- build/regeneration scripts
- model-specific documentation

## Notes

- This is a monorepo rooted at `BMI/`.
- Shared conventions (naming, scripts, CI, and docs) will be aligned as additional models are added.
