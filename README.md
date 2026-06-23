# BMI Model Wrappers Monorepo

This repository contains Python BMI wrapper projects for hydrological models (C/C++/Fortran).

## Purpose

This monorepo is used to:

- Build and maintain Python-accessible BMI wrappers for multiple models
- Keep each model implementation isolated while following shared conventions
- Standardize regeneration, build, test, and packaging workflows
- Make onboarding easier for future model wrappers (for example, NOAH-OWP)

## Repository Layout

```text
BMI/
├── README.md                  # Monorepo overview (this file)
├── .gitignore
├── CFE/                       # CFE BMI wrapper (C)
│   ├── README.md
│   ├── QUICKSTART.md
│   ├── babel.toml
|   ├── Dockerfile
│   ├── regen_and_build.sh
│   ├── post_babelize_patch.sh
│   ├── install.sh
│   └── pymt_cfe/
└── NOAH_OWP/                  # Noah-OWP BMI wrapper (Fortran)
│   ├── README.md
│   ├── QUICKSTART.md
│   ├── babel.toml
│   ├── Dockerfile
│   ├── regen_and_build.sh
│   ├── post_babelize_patch.sh
│   ├── install.sh
│   └── pymt_noah_owp/
└── SOIL-FREEZE-THAW/           # SoilFreezeThaw BMI wrapper (C++)
    ├── README.md
    ├── QUICKSTART.md
    ├── babel.toml
    ├── Dockerfile
    ├── regen_and_build.sh
    ├── post_babelize_patch.sh
    ├── install.sh
    └── pymt_sft/
```

## Current Model Status

| Model | Language | Package | Status |
|---|---|---|---|
| [CFE](https://github.com/NOAA-OWP/cfe) | C | `pymt_cfe` | ✅ Working |
| [Noah-OWP Modular](https://github.com/NOAA-OWP/noah-owp-modular) | Fortran | `pymt_noah_owp` | ✅ Working |
| [Soil Freeze Thaw](https://github.com/NOAA-OWP/SoilFreezeThaw) | `pymt_sft` | ✅ Working |

## Model Project Conventions

Each model folder should include:

- A model-specific `README.md`
- A model-specific `babel.toml`
- A generated/maintained Python package (`pymt_<model>`)
- Helper scripts for regenerate/build/test (as needed)

## Contribution / Workflow

1. Create a model folder at repo root (example: `NOAH_OWP/`).
2. Add model-specific `babel.toml` and package naming (`pymt_<model>`).
3. Regenerate wrapper code with Babelizer.
4. Apply local patches (if required for packaging/runtime).
5. Build and test in a clean environment (or Docker).
6. Commit only source/config/docs (not build artifacts).

## Git Hygiene

- Track source code, configuration, and docs.
- Do **not** track generated artifacts (`build/`, `dist/`, `*.egg-info`, `__pycache__`, compiled binaries).
- Keep one git repository at `BMI/` root (no nested `.git` repositories).
