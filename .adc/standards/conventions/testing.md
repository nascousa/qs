# Testing Conventions

## Current Baseline

QS ships a lightweight non-GUI smoke test for integrated TEAM index behavior. For documentation-only ADC updates, runtime GUI testing is not required.

## Required Checks for Script Changes

Run parse-only validation before and after PowerShell script changes:

```powershell
Set-Location D:\Repos\QuickSearch
[scriptblock]::Create((Get-Content -LiteralPath .\src\QuickSearch.ps1 -Raw)) | Out-Null
[scriptblock]::Create((Get-Content -LiteralPath .\src\QuickSearch.Support.ps1 -Raw)) | Out-Null
Get-Content -LiteralPath .\src\settings\config.json -Raw | ConvertFrom-Json | Out-Null
Get-ChildItem -LiteralPath .\src\profiles -File -Filter '*.profile.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null }
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke-index.ps1
```

## Preferred Harness

- Use Pester for PowerShell tests when adding or changing behavior.
- Place tests under `tests/` at the repository root.
- Keep UI-independent logic testable outside Windows Forms event handlers when making larger changes.
- Add fixtures under `tests/fixtures/`.
- Keep tests deterministic and independent of real mapped-drive contents.
- Keep smoke tests free of real mapped-drive dependencies by creating temporary fixtures at runtime.

## Required Coverage Areas

- Configuration and version loading from `src/settings/config.json`, plus selectable profile loading from `src/profiles/*.profile.json`.
- Drive/path construction for ALL, TSG, SOP, CASE, and TEAM searches.
- Generated index schema and lookup behavior.
- Ignored filename/folder handling.
- Result selection, text/HTML/Markdown file preview, active search keyword highlighting, and open-path normalization.

## Manual UI Smoke Check

For Windows Forms UI changes, include manual validation evidence:

- Form launches successfully.
- Search button executes without an unhandled exception.
- Filename search returns expected results.
- Content search handles no-match and match cases.
- Result click loads preview content, including HTML files and Markdown files with HTML tags.
- Result preview highlights the active search keyword when that keyword is present in the file body.
- Open button launches the selected file only when the selected path is expected.
