# BMI Model Wrappers Monorepo

This repository contains Python BMI wrapper projects for hydrological models (C/C++/Fortran).

## Purpose

This monorepo is used to:

- Build and maintain Python-accessible BMI wrappers for multiple models
- Keep each model implementation isolated while following shared conventions
- Standardize regeneration, build, test, and packaging workflows
- Make onboarding easier for future model wrappers

## Repository Layout

```text
BMI/
├── README.md                  # Monorepo overview (this file)
├── .gitignore
├── CFE/                        # CFE BMI wrapper (C)
│   ├── README.md
│   ├── QUICKSTART.md
│   ├── babel.toml
│   ├── Dockerfile
│   ├── regen_and_build.sh
│   ├── post_babelize_patch.sh
│   ├── install.sh
│   └── pymt_cfe/
├── LASAM/                      # LASAM/LGAR BMI wrapper (C++)
│   ├── README.md
│   ├── QUICKSTART.md
│   ├── babel.toml
│   ├── Dockerfile
│   ├── regen_and_build.sh
│   ├── post_babelize_patch.sh
│   ├── install.sh
│   └── pymt_lasam/
├── NOAH_OWP/                   # Noah-OWP-Modular BMI wrapper (Fortran)
│   ├── README.md
│   ├── QUICKSTART.md
│   ├── babel.toml
│   ├── Dockerfile
│   ├── regen_and_build.sh
│   ├── post_babelize_patch.sh
│   ├── install.sh
│   └── pymt_noah_owp/
├── PET/                        # PET / Evapotranspiration BMI wrapper (C)
│   ├── README.md
│   ├── QUICKSTART.md
│   ├── babel.toml
│   ├── Dockerfile
│   ├── regen_and_build.sh
│   ├── post_babelize_patch.sh
│   ├── install.sh
│   └── pymt_pet/
├── SAC_SMA/                    # Sac-SMA BMI wrapper (Fortran)
│   ├── README.md
│   ├── QUICKSTART.md
│   ├── babel.toml
│   ├── Dockerfile
│   ├── regen_and_build.sh
│   ├── post_babelize_patch.sh
│   ├── install.sh
│   └── pymt_sac_sma/
├── SNOW17/                     # Snow17 BMI wrapper (Fortran)
│   ├── README.md
│   ├── QUICKSTART.md
│   ├── babel.toml
│   ├── Dockerfile
│   ├── regen_and_build.sh
│   ├── post_babelize_patch.sh
│   ├── install.sh
│   └── pymt_snow17/
├── SOIL-FREEZE-THAW/           # SoilFreezeThaw BMI wrapper (C++)
│   ├── README.md
│   ├── QUICKSTART.md
│   ├── babel.toml
│   ├── Dockerfile
│   ├── regen_and_build.sh
│   ├── post_babelize_patch.sh
│   ├── install.sh
│   └── pymt_sft/
├── SOIL-MOISTURE-PROFILES/     # SoilMoistureProfiles BMI wrapper (C++)
│   ├── README.md
│   ├── QUICKSTART.md
│   ├── babel.toml
│   ├── Dockerfile
│   ├── regen_and_build.sh
│   ├── post_babelize_patch.sh
│   ├── install.sh
│   └── pymt_smp/
├── TOPMODEL/                   # TOPMODEL BMI wrapper (C)
│   ├── README.md
│   ├── QUICKSTART.md
│   ├── babel.toml
│   ├── Dockerfile
│   ├── regen_and_build.sh
│   ├── post_babelize_patch.sh
│   ├── install.sh
│   └── pymt_topmodel/
└── UEB/                        # UEB BMI wrapper (C++)
    ├── README.md
    ├── QUICKSTART.md
    ├── babel.toml
    ├── Dockerfile
    ├── regen_and_build.sh
    ├── post_babelize_patch.sh
    ├── install.sh
    └── pymt_ueb/
```

## Model Project Conventions

Each model folder should include:

- A model-specific `README.md`
- A model-specific `babel.toml`
- A generated/maintained Python package (`pymt_<model>`)
- Helper scripts for regenerate/build/test (as needed)

## Contribution / Workflow

1. Create a model folder at repo root (example: `PET/`).
2. Add model-specific `babel.toml` and package naming (`pymt_<model>`).
3. Regenerate wrapper code with Babelizer.
4. Apply local patches (if required for packaging/runtime).
5. Build and test in a clean environment (or Docker).
6. Commit only source/config/docs (not build artifacts).

## Git Hygiene

- Track source code, configuration, and docs.
- Do **not** track generated artifacts (`build/`, `dist/`, `*.egg-info`, `__pycache__`, compiled binaries).
- Keep one git repository at `BMI/` root (no nested `.git` repositories).
