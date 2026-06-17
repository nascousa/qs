# Technical Debt and Known Issues

The following risks were observed during ADC onboarding. Do not perform broad refactors without explicit scope, tests, and validation.

## Known Issues

- File preview reads the full selected file into memory and may freeze the UI on large files.
- Markdown preview uses a lightweight built-in renderer, not a full CommonMark implementation.
- Non-TEAM filename and content searches still scan the selected mapped-drive folder recursively and can be slow on large folders.
- TEAM re-indexing extracts top-word tags by streaming file contents; unreadable files are skipped for tags, and large folders can take time.
- Generated tags use simple English word frequency and do not yet apply stop-word filtering.
- `src/QuickSearch.bat` references `QuickSearch_UI.ps1`, but that file is not present in the current workspace.
- A lightweight non-GUI smoke test exists for TEAM index behavior, but there is no full Pester suite or GUI automation yet.

## No-Touch Zones

- Do not refactor the Windows Forms UI event handlers broadly during ADC-only tasks.
- Do not change mapped-drive roots without explicit confirmation from the human.
- Do not delete generated indexes as part of unrelated work.
