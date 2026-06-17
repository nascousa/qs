# Common Errors Runbook

## Script Execution Is Blocked

Symptom: PowerShell refuses to run `src/QuickSearch.ps1`.

Use the local bypass command:

```powershell
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\QuickSearch.ps1
```

## Windows Forms Cannot Load

Symptom: `Add-Type -assembly System.Windows.Forms` fails.

Actions:

1. Confirm the script is running on Windows desktop with .NET Windows Forms support.
2. Try Windows PowerShell 5.1 if PowerShell 7 cannot load the assembly in the current environment.
3. Record the shell version and error message in the session scratchpad.

## Mapped Drive Is Missing

Symptom: search returns no results or path access errors.

Actions:

1. Confirm the selected drive exists in File Explorer or with `Test-Path`.
2. Confirm the expected folder, such as `Orcas_Main\TSG-SOP`, exists under that drive.
3. Do not change hardcoded defaults until the desired target path is confirmed.

## JSON Config Fails To Parse

Symptom: startup fails while reading config.

Validate JSON:

```powershell
Get-Content -LiteralPath .\src\settings\config.json -Raw | ConvertFrom-Json | Out-Null
Get-ChildItem -LiteralPath .\src\profiles -File -Filter '*.profile.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null }
```

## Team Folder Search Fails

Symptom: team filename search errors or produces no indexed results.

Actions:

1. See `.adc/knowledge/known-issues.md`; the current script has known index schema and typo risks that should be fixed in a stabilization change.
2. Confirm any generated index is current and uses the expected schema.
3. Do not treat generated indexes as canonical source.

## Generated Index Looks Stale

Symptom: search results do not reflect current file contents.

Actions:

1. Use the QS re-index action only against the intended mapped-drive folder.
2. Confirm `src/settings/config.json` `ProfileName` and the selected `src/profiles/*.profile.json` point to the intended search roots.
3. Treat `src/data/index.json` as generated and reproducible.
