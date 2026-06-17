# Project Roadmap

## Milestone 1: ADC Onboarding

- Maintain `.adc/` project context and AI/tool pointer files.
- Keep QS architecture, bootstrap, conventions, known issues, and diagrams current.
- Keep project rules in sync with ADC 1.1.27 until a newer ADC standard is explicitly adopted.

## Milestone 2: Stabilization Safety Net

- Add safe validation for PowerShell parsing and JSON configuration loading.
- Create a small local fixture folder for deterministic search tests.
- Add Pester tests if dependency approval is granted or Pester is already present on target machines.

## Milestone 3: Legacy Search Fixes

- Fix documented search-path and indexing defects without changing the user workflow.
- Normalize generated index schema used by `src/QuickSearch.ps1`.
- Add bounded previews so large files do not freeze the UI.
- Decide whether `src/QuickSearch.bat` should be repaired, removed, or documented as experimental.

## Milestone 4: Packaging and Release Discipline

- Define a deterministic packaging flow for the QS script bundle.
- Keep generated indexes out of release source unless intentionally bundled.
- Update version numbers and README date during every release or publish workflow.

## Milestone 5: ContextGraph Integration

- Register QS in CGA when project credentials are available.
- Run one full-project index, then use incremental indexing for future changes.
- Record change summaries, validation evidence, release events, blockers, and risks through CGA-Relay.
