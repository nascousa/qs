# Project Structure Conventions

## Current Layout

QS is a legacy desktop script utility. Existing root-level scripts are accepted for compatibility:

```text
QuickSearch/
├── .adc/
├── .github/
├── docs/
├── README.md
└── src/
    ├── QuickSearch.ps1
    ├── QuickSearch.Support.ps1
    ├── QuickSearch.bat
    ├── data/
    ├── profiles/
    │   ├── default.profile.json
    │   └── *.profile.json
    └── settings/
        └── config.json
└── tests/
    └── smoke-index.ps1
```

## Rules

- Preserve `src/QuickSearch.ps1` as the launch entry point until a tested migration plan exists.
- Keep `src/QuickSearch.Support.ps1` beside the entry script because `src/QuickSearch.ps1` dot-sources it at startup.
- Keep runtime modules focused and readable; the old 25000-character transfer split limit no longer controls source layout unless a maintainer explicitly asks for it.
- Keep ADC context under `.adc/`; do not place application source inside `.adc/`.
- Keep generated runtime outputs such as `index.json` out of canonical documentation unless explicitly promoted as fixtures.
- New user-facing documentation belongs in `docs/` if it grows beyond README scope.
- New automated tests belong in `tests/`.
- New temporary data belongs in `tmp/` and must remain git-ignored.
- New utility scripts should live under `src/tools/` when they are not part of the QS runtime launch path.
- If future launch wrappers are added at the repository root, keep them thin and point them to `src/QuickSearch.ps1`.
- Never write real secrets or machine-specific credentials into tracked files.

## Environment Files

- `.env` is for local-only values and must stay ignored.
- Any new environment variable must be documented with a dummy example before use.
- ContextGraph credentials must be injected through environment variables and never committed.
