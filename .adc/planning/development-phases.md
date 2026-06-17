# Development Phases

## Phase 1: ADC Onboarding

- Create and maintain ADC 1.1.27 structure.
- Document entry points, bootstrap steps, current risks, and standards.
- Add root rule pointers for common AI tools.
- Add MCP profile and operational scratchpad placeholders.

## Phase 2: Safety Net

- Add parse-only validation commands for scripts.
- Add JSON schema expectations for configuration and index files.
- Introduce Pester tests for pure script functions when practical.
- Create deterministic fixtures for search behavior checks.
- Document manual UI verification evidence for Windows Forms behavior.

## Phase 3: Legacy Fixes

- Repair confirmed typos such as stale cmdlet or parameter names.
- Normalize generated index schema used by `src/QuickSearch.ps1`.
- Make file preview bounded and resilient to encoding errors.
- Add safe handling for empty selections and non-file result messages.
- Validate `src/QuickSearch.bat` and either restore the referenced script or mark the launcher retired.

## Phase 4: Release Discipline

- Add packaging scripts only after the source layout is stable.
- Update README version/date for every release.
- Record release evidence through CGA-Relay when credentials are configured.
- Keep generated or local-only files excluded from source control.
