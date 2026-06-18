# QuickSearch (QS)

**Version:** v1.4.45  
**Date:** 2026-06-18  
**Status:** Air-gapped, pure PowerShell desktop search tool for mapped team folders  
**ADC Standard:** 1.1.27  

QuickSearch is built for air-gapped and offline Windows environments. It is written in PowerShell, runs from local files, and does not require third-party libraries, package managers, installers, databases, web services, or cloud services.

QuickSearch helps find files on mapped shared drives. It can search by filename, search generated TEAM tags quickly, scan file contents when needed, preview matched files, and open the selected file.

## Air-Gapped Fit

- Pure PowerShell desktop utility using built-in Windows/.NET capabilities.
- No third-party runtime libraries or external services are required for normal use.
- No internet access is required after the files are present on the target machine.
- Settings, profiles, and generated indexes are local JSON files under `src/`.

## Start

For normal use, double-click:

```text
src\QuickSearch.vbs
```

For debugging from a console:

```powershell
Set-Location D:\Repos\QuickSearch
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\QuickSearch.ps1
```

The window title uses the `Version` value from `src/settings/config.json`, for example `QuickSearch v1.4.45`.

## Main Buttons

- `Search` runs the selected search.
- `Index` opens TEAM index settings and includes `Re-Index Team Folder`.
- `Show Preview` / `Hide Preview` toggles the file preview pane.
- `Settings` selects the active runtime profile.
- `About` shows author, contact, and basic usage information.
- `Open` opens the selected result.

Prompts, settings dialogs, and progress windows open centered over the main QuickSearch window.

## Search Modes

- `Filename/Tags (Quick)` is the fast path. For `TEAM`, it uses the generated index at `src/data/index.json`.
- `Content (Slow)` reads file contents at search time. Use it when you need to find text inside files.
- `Scope` applies to `ALL` live scans. `Configured Types` scans configured folders such as TSG, SOP, and CASE. `All` scans the full selected root.

If TEAM quick search says the index is missing, open `Index` and run `Re-Index Team Folder`.

## Index

The `Index` popup lets you edit:

- TEAM path
- top words per file
- ignored filenames
- allowed extensions
- ignored extensions
- ignored folders

`Re-Index Team Folder` rebuilds `src/data/index.json`. The index stores filenames, paths, and generated top-word tags. It does not store full file contents.

The Index popup also shows current index data such as indexed file count, generated tag count, search term count, schema version, update time, and file size.

## Preview

Selecting a result opens the preview pane automatically. QS previews plain text, Markdown, and HTML files. When the selected file contains the active search keyword, the preview highlights it. Use the preview search box and Find button to highlight a different word or phrase inside the current preview.

## Settings And Profiles

- Main config: `src/settings/config.json`
- Profiles: `src/profiles/*.profile.json`
- Default profile: `src/profiles/default.profile.json`

Profiles are for environment-specific values such as drive letter, document path, TEAM path, and type list. Global search and indexing defaults stay in `src/settings/config.json` unless a profile intentionally overrides them.

## Validation

Run the main smoke test after changing runtime code:

```powershell
Set-Location D:\Repos\QuickSearch
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke-index.ps1
```

Archived helper tools live under `src/tools/`. Only run their smoke tests when those tools change.

## Project Notes

QS is onboarded to ADC under `.adc/`. Before changing code, read `.adc/index.md`, `.adc/prompt-rules.md`, and the relevant scoped standards under `.adc/standards/`.

Generated index files are runtime data. Do not commit secrets, mapped-drive credentials, real ContextGraph credentials, release payloads, or transfer artifacts.
