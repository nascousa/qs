# Project Status

**Current Phase:** refined main-window search layout, About popup, simplified README, selectable profiles, unified Index popup, optimized Live Content Scan, and archived helper tools
**Project Version:** v1.4.42
**ADC Standard:** 1.1.27
**Date:** 2026-06-18

## Active Goals

- Preserve the current QS Windows PowerShell desktop workflow.
- Keep top-word indexing integrated into QS through the Index popup instead of a separate maintenance surface.
- Keep QS discoverable to AI assistants through ADC project context.
- Prepare QS for ContextGraph/CGA-Relay indexing and change aggregation.
- Document known script risks before functional fixes are attempted.
- Add a future validation safety net before changing runtime behavior.

## Recent Changes

- 2026-06-15: Onboarded QS to ADC 1.1.27 with project-specific planning, standards, knowledge, diagrams, and CGA MCP profile files.
- 2026-06-16: Cleaned duplicated ADC onboarding content and aligned README/version/date metadata.
- 2026-06-16: Merged TagManager-style top-word indexing into `src/QuickSearch.ps1`, normalized `src/settings/config.json`, and made TEAM quick search use `src/data/index.json` filename/path/tag matches.
- 2026-06-16: Added `tests/smoke-index.ps1`, a non-GUI smoke test for index generation, ignored-file filtering, generated tags, and indexed lookup.
- 2026-06-16: Added a `TagManager` UI button and settings popup for TEAM path, top words per file, ignored filenames, ignored extensions, ignored folders, config save, and index rebuild.
- 2026-06-16: Added lightweight Markdown preview rendering for `.md` and `.markdown` files in the right-side preview pane.
- 2026-06-16: Added a collapsible preview pane that is hidden by default, can be toggled with `Show Preview` / `Hide Preview`, and auto-expands when a file result is selected.
- 2026-06-16: Added an indexing wait popup for both `Re-Index Team Folder` and TagManager `Rebuild Index` actions.
- 2026-06-16: Repaired `src/QuickSearch.bat` so it launches the current `src/QuickSearch.ps1` entry point instead of the removed `QuickSearch_UI.ps1` script.
- 2026-06-16: Split the PowerShell source into `src/QuickSearch.ps1` and `src/QuickSearch.Support.ps1`, keeping both files under 25000 characters while preserving `src/QuickSearch.ps1` as the launch entry point.
- 2026-06-16: Corrected QS version display to unpadded `vX.Y.Z`; future routine increments advance the patch segment until `999` before carrying to the minor segment.
- 2026-06-16: Added `src/QuickSearch.TextTransfer.ps1` and `tests/smoke-text-transfer.ps1` for ZIP/Base64 text-only transfer encode/decode validation.
- 2026-06-16: Added `src/QuickSearch.Payload.ps1` and `tests/smoke-payload.ps1` for minified PowerShell source to UTF-8 Brotli Base64 payload packaging and decode validation.
- 2026-06-16: Added `src/QuickSearch.Payload.bat` so double-clicking generates the current versioned Brotli/Base64 payload under `release\`.
- 2026-06-16: Updated `src/QuickSearch.TextTransfer.ps1` so oversized Base64 release output is split into a manifest plus 25000-character-safe part files.
- 2026-06-16: Added `src/QuickSearch.Index.ps1` and upgraded TEAM quick search to schema v2 `documents` plus inverted `terms`, with unchanged-file tag metadata reuse and legacy index search compatibility.
- 2026-06-16: Updated TEAM top-word extraction to stream file content through a bounded buffer instead of reading full files and splitting all words in memory.
- 2026-06-16: Added `src/QuickSearch.UltraTransfer.ps1` and `tests/smoke-ultra-transfer.ps1` for optional high-compression file or folder transfer.
- 2026-06-16: Clarified that the default outgoing QS release artifact is only the lightweight `release/<project-version>-payload.txt` source payload.
- 2026-06-16: Moved optional TextTransfer and UltraTransfer default outputs to `tmp\transfer\` so `release\` remains clean for the outgoing lightweight payload.
- 2026-06-16: Split the payload batch launcher into explicit encode and decode launchers: `src/QuickSearch.Payload.Encode.bat` and `src/QuickSearch.Payload.Decode.bat`.
- 2026-06-16: Moved canonical runtime paths to `src/settings/config.json`, selectable `src/profiles/*.profile.json`, and generated `src/data/index.json`.
- 2026-06-16: Moved the QS runtime and payload version source to `src/settings/config.json` `Version`.
- 2026-06-16: Moved TEAM index rebuilds behind a background PowerShell job so the wait popup stays responsive during long indexing runs.
- 2026-06-16: Added progress counts, stage reporting, cancel support, and temporary-file replacement for TEAM index rebuilds.
- 2026-06-16: Added current-file progress reporting and `MaxTagFileSizeMB` so large new or changed files do not stall tag extraction while still being indexed by name/path.
- 2026-06-16: Added `AllowedFileExtNames` extension whitelist indexing and `src/data/index.sample.json` as a schema v2 reference instance.
- 2026-06-16: Added `src/QuickSearch.Preview.ps1` with HTML preview rendering, Markdown-with-HTML preview support, and content-search keyword highlighting.
- 2026-06-16: Added `src/QuickSearch.IndexResume.ps1` for resumable `index.json.tmp` checkpoints and unchanged-file metadata reuse during TEAM index rebuilds.
- 2026-06-16: Added `src/QuickSearch.Profile.ps1`, `ProfileName`, and a main-window `Settings` button for selecting `src/profiles/*.profile.json`, defaulting to `default.profile.json`.
- 2026-06-17: Updated `src/QuickSearch.bat` so double-click launch starts the companion PowerShell console minimized while the QS UI opens normally.
- 2026-06-17: Updated `src/QuickSearch.ps1` so closing the QS UI exits the companion console by default, with `QS_PAUSE_ON_EXIT=1` available for debug pauses.
- 2026-06-17: Added `src/QuickSearch.vbs` as a no-console UI launcher and updated `src/QuickSearch.bat` to delegate to it for compatibility.
- 2026-06-17: Moved Search button work to a background PowerShell job with a cancelable progress dialog and batched result-list updates so long searches no longer freeze the UI.
- 2026-06-17: Removed duplicated elapsed-time text from the search progress dialog body; elapsed time remains in the dialog title bar.
- 2026-06-17: Clarified UI and documentation so content search is labeled as a live scan, while the TEAM index is documented as filenames, paths, and generated top-word tags rather than a full-text content index.
- 2026-06-17: Updated preview keyword highlighting so any active search keyword is highlighted when a result is selected, not only Live Content Scan results.
- 2026-06-17: Updated the keyword search box to behave as a placeholder, clearing `keyword` on focus and restoring it on empty blur.
- 2026-06-17: Updated preview keyword highlighting so highlighted search keywords are also bold in text and HTML preview modes.
- 2026-06-17: Updated Live Content Scan to filter candidate files through runtime allowed/ignored settings and stop reading each file after the first simple keyword match.
- 2026-06-17: Moved legacy payload, ZIP/Base64, and UltraTransfer helpers into `src/tools/` for manual reuse; QS no longer has a default release payload or split-transfer workflow.
- 2026-06-17: Updated Live Content Scan with `MaxSearchResults`, `MaxContentScanFileSizeMB`, TEAM index candidate reuse, a `Scope` selector for ALL scans, expanded default ignored folders/extensions, ignored-folder traversal pruning, and optional ripgrep acceleration with PowerShell fallback.
- 2026-06-17: Renamed the main-window `TagManager` entry to `Index` and moved the `Re-Index Team Folder` action into the Index settings popup.
- 2026-06-17: Removed duplicated ignored-folder defaults from profile files so global ignore/search policy stays in `src/settings/config.json` unless a profile intentionally overrides it.
- 2026-06-17: Added process-local parsed JSON caching for TEAM quick index searches, materialized schema v2 matches in a single document pass, and normalized reusable index timestamp comparison after JSON parsing.
- 2026-06-17: Moved the top `Status` label and status textbox 10px left so the controls are less crowded against the right edge.
- 2026-06-17: Rewrote README as a shorter user guide focused on starting QS, choosing search modes, maintaining the Index popup, previewing files, and validating changes.
- 2026-06-18: Added a top-level `About` button next to `Settings` with author, email, and basic usage guidance.
- 2026-06-18: Widened the keyword search box and moved the Scope/search/action/status control group 10px left.
- Validation passed for QS 1.4.42 with recursive PowerShell parse checks for `src/`, JSON parse checks for settings/profiles/sample index, `tests/smoke-index.ps1`, and `tests/smoke-payload.ps1`.

## Current Validation State

- Validation passed for QS 1.4.42 with recursive PowerShell parse checks for `src/`, JSON parse checks for settings/profiles/sample index, `tests/smoke-index.ps1`, and `tests/smoke-payload.ps1`. Manual UI smoke testing is still recommended on a machine with the expected mapped drives.
- Manual UI smoke testing is still recommended on a machine with the expected mapped drives.

## Current Risks

- QS has a lightweight non-GUI index smoke test, but no full Pester suite yet.
- First-time TEAM re-indexing on large mapped-drive folders can still be slow, but interrupted rebuilds now leave `index.json.tmp` checkpoint data that the next rebuild can reuse.
- Live Content Scan is still a live content read, but it is now bounded and can avoid full TEAM enumeration when a current TEAM index exists.
- Mapped-drive availability is environment-specific and must be validated manually.
