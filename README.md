# QuickSearch (QS)

**Version:** v1.4.34  
**Status:** ADC onboarded, selectable runtime profiles, TEAM quick search upgraded to streaming schema v2 inverted index, archived release and transfer helpers moved to src/tools, smoke-tested  
**Date:** 2026-06-17  
**ADC Standard:** 1.1.27

QuickSearch (QS) is a Windows PowerShell desktop utility for searching mapped-drive team folders, previewing matched file contents, rendering text, HTML, and Markdown previews, and maintaining a local TEAM folder streaming inverted tag index. It targets Orcas-style shared folders, especially `Orcas_Main\TSG-SOP` and `Orcas_Main\team`.

The main window title shows the project version from `src/settings/config.json` `Version` in unpadded form such as `QuickSearch v1.4.34`, so updating the config version updates the title bar on the next launch. QS version increments advance the patch segment first; only after patch `999` does the minor segment carry forward.

## Entry Points

- `src/QuickSearch.ps1` - Main Windows Forms entry script and UI shell for TSG, SOP, CASE, and TEAM folders.
- `src/QuickSearch.Support.ps1` - Support functions for config, version title formatting, search, and TagManager settings.
- `src/QuickSearch.Preview.ps1` - Preview helper for RichTextBox text/Markdown rendering, WebBrowser HTML rendering, Markdown files with HTML tags, and active search keyword highlighting.
- `src/QuickSearch.Profile.ps1` - Selectable profile helper for discovering `*.profile.json` files, applying profile overlays, persisting the chosen profile, and showing the Profile Settings popup.
- `src/QuickSearch.Async.ps1` - Background indexing dialog helper that polls progress, keeps the UI responsive, and supports canceling an index rebuild.
- `src/QuickSearch.IndexStatus.ps1` - Lightweight status writer used by index rebuilds to report progress to the UI.
- `src/QuickSearch.IndexPolicy.ps1` - Index policy helper for extension whitelist and configurable tag extraction limits.
- `src/QuickSearch.IndexResume.ps1` - Resumable index checkpoint helper that writes and completes `index.json.tmp` safely.
- `src/QuickSearch.Index.ps1` - TEAM index module that writes schema v2 `documents` plus inverted `terms`, streams target files for top-word extraction, reuses unchanged file tag metadata, and keeps old index search compatibility.
- `src/QuickSearch.Search.ps1` - Filesystem search helper used by the UI and background search job for filename and file-content searches.
- `src/settings/config.json` and `src/profiles/*.profile.json` - Local configuration files for version, selected profile name, UI defaults, mapped-drive paths, allowed/ignored files, and tag count settings. The default profile is `src/profiles/default.profile.json`.
- `src/data/index.sample.json` - Schema v2 sample index file for reference; runtime rebuilds still write `src/data/index.json`.
- `src/QuickSearch.vbs` - No-console Windows Script Host launcher that opens the QS UI through hidden PowerShell.
- `src/QuickSearch.bat` - Compatibility batch launcher that delegates to `src/QuickSearch.vbs`.
- `tests/smoke-index.ps1` - Non-GUI smoke test for TEAM index generation and tag lookup.

The PowerShell runtime is organized into responsibility-focused modules. QS no longer has a default release payload or text-splitting workflow.

## Archived Tools

The old release payload and text-transfer helpers are retained under `src/tools/` for manual reuse only. Do not generate files under `release/` or create split transfer artifacts unless a maintainer explicitly asks for that workflow.

- `src/tools/QuickSearch.Payload.ps1` - PowerShell 7+ utility for minifying QS PowerShell source, encoding it as UTF-8, compressing it with Brotli, and decoding the payload back to source.
- `src/tools/QuickSearch.Payload.Encode.bat` - Archived double-click payload encode launcher.
- `src/tools/QuickSearch.Payload.Decode.bat` - Archived double-click payload decode launcher.
- `src/tools/QuickSearch.TextTransfer.ps1` - Archived Windows PowerShell 5.1-compatible ZIP/Base64 transfer utility.
- `src/tools/QuickSearch.UltraTransfer.ps1` - Archived PowerShell 7+ Brotli/Base64 transfer utility.

Archived tool smoke tests are kept in `tests/smoke-text-transfer.ps1`, `tests/smoke-ultra-transfer.ps1`, and `tests/smoke-payload.ps1` for changes that touch `src/tools/`.

## Preview

QS keeps the right-side preview pane collapsed by default so the results list can use the full window width. Selecting a file automatically expands the preview pane, and the `Show Preview` / `Hide Preview` button can manually toggle it. Plaintext files render in a RichTextBox. HTML files with `.html` or `.htm` extensions render in a WebBrowser preview, and Markdown files with embedded HTML tags use the same HTML preview path. Plain Markdown still renders into RichTextBox RTF with lightweight support for headings, lists, block quotes, code blocks, inline code, bold, and italic text. When a search keyword is active, selecting a result highlights that keyword in the preview and renders the highlighted keyword in bold.

## Profiles

QS loads `src/settings/config.json`, then applies the selected profile from `src/profiles`. The selected profile name is stored in `ProfileName`; when it is missing or points to a missing file, QS falls back to `default.profile.json`. Use the `Settings` button in the main window to select a different `*.profile.json` file. Applying a profile updates the drive letter, document path, TEAM path, type list, and related profile-controlled defaults for the current session, then saves the selected profile name back to `src/settings/config.json`.

## Integrated Tag Index

The `Re-Index Team Folder` action writes `src/data/index.json` as generated runtime data. The current schema stores a `documents` table with file metadata plus generated `tags` and `tagCounts`, and a `terms` table that maps searchable words to document ids. TEAM quick search uses this inverted index to match filenames, paths, and generated tags without scanning every file on each search. A reference schema instance is available at `src/data/index.sample.json`.

The search box uses `keyword` as placeholder text. Focusing the search box clears the placeholder for typing, and leaving it empty restores the placeholder. Searches treat the placeholder as an empty keyword instead of searching for the literal word `keyword`.

Search actions run in a background PowerShell job with a cancelable progress dialog, so long mapped-drive filename scans and Live Content Scan searches no longer block the Windows Forms UI thread while they run. The progress dialog keeps elapsed time in the title bar and keeps the body text to the active search message. QS batches result-list updates after the background search completes to avoid slow per-row UI redraws.

The index does not persist full source file text. It stores filenames, paths, and generated top-word tags for indexed TEAM files, so it is not a full-text content index. `AllowedFileExtNames` in `src/settings/config.json` is an extension whitelist for indexed files; when it is non-empty, files outside the whitelist are skipped. Top-word extraction streams target file content through a small read buffer instead of splitting the whole file into an in-memory word array. Rebuilds compare unchanged file size and timestamps so unchanged files reuse the previous document metadata instead of reading content again. New or changed files larger than `MaxTagFileSizeMB` skip generated tag extraction by default, but they are still indexed by filename and path when their extension is allowed.

Use `Filename/Tags (Quick)` for the index-backed TEAM path. `Live Content Scan (Slow)` is intentionally a live recursive scan and can still be slower on large mapped-drive folders, especially when `Type` is `ALL`. To reduce needless reads, Live Content Scan applies the same allowed extensions, ignored extensions, ignored filenames, and ignored folder parts from the runtime config before scanning file text, then stops reading each file as soon as the first simple keyword match is found.

Use the `TagManager` button to open settings for TEAM path, top words per file, ignored filenames, allowed extensions, ignored extensions, and ignored folders. The popup can save `src/settings/config.json` and rebuild the TEAM index.

Index rebuilds can take a long time on large TEAM folders. QS runs the rebuild in a background PowerShell job and keeps the popup responsive while indexing is running. The popup reports the scan/index/write stage, processed file counts, indexed, reused, and skipped totals, elapsed time, current file name, and a Cancel button. During indexing, QS writes resumable checkpoints to `src/data/index.json.tmp`; if indexing is interrupted, the next rebuild can reuse that checkpoint plus the last completed index. The generated index replaces `src/data/index.json` only after the final checkpoint is complete.

## Local Use

```powershell
Set-Location D:\Repos\QuickSearch
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\QuickSearch.ps1
```

For a no-console UI launch, double-click `src\QuickSearch.vbs`. It starts PowerShell hidden and shows only the Windows Forms UI. `src\QuickSearch.bat` is a compatibility launcher that delegates to the VBS launcher; because batch files are console programs, double-clicking the batch file may still briefly show a `cmd.exe` window before it exits. Closing the UI exits the hidden PowerShell process by default. For debugging with a visible console, run PowerShell directly and set `QS_PAUSE_ON_EXIT=1` when you want the console to stay open after the UI closes.

```powershell
$env:QS_PAUSE_ON_EXIT = '1'
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\QuickSearch.ps1
```

## Validation

```powershell
Set-Location D:\Repos\QuickSearch
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke-index.ps1
```

When changing archived helpers under `src/tools/`, also run their smoke tests:

```powershell
Set-Location D:\Repos\QuickSearch
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke-text-transfer.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke-ultra-transfer.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke-payload.ps1
```

## ADC Context

QS is onboarded to Autonomous Development Constitution (ADC) standard 1.1.27 under `.adc/`. Before making changes, read `.adc/index.md` and `.adc/prompt-rules.md`, then follow the scoped standards under `.adc/standards/`.

When ContextGraph credentials are configured, QS change information must be aggregated into CGA through CGA-Relay, including indexing, change summaries, progress notes, validation evidence, release events, blockers, and risks.
