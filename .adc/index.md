---
project-name: "QuickSearch"
project-alias: "QS"
version: "1.4.51"
adc-standard-version: "1.1.27"
description: "A Windows PowerShell desktop utility for searching mapped shared-drive documents, rendering collapsible text, HTML, and Markdown previews, and maintaining an integrated streaming TEAM inverted tag index."
tech-stack:
  - Windows PowerShell 5.1+
  - PowerShell 7+ only for archived Brotli helper tools under src/tools
  - .NET Windows Forms
  - JSON configuration files
  - Windows mapped drives
architecture-style: "Single-machine desktop utility"
entry-points:
  - src/QuickSearch.ps1
  - src/QuickSearch.IndexStatus.ps1
  - src/QuickSearch.IndexPolicy.ps1
  - src/QuickSearch.IndexResume.ps1
  - src/QuickSearch.Index.ps1
  - src/QuickSearch.Search.ps1
  - src/QuickSearch.Async.ps1
  - src/QuickSearch.Preview.ps1
  - src/QuickSearch.Profile.ps1
  - src/tools/QuickSearch.TextTransfer.ps1
  - src/tools/QuickSearch.UltraTransfer.ps1
  - src/tools/QuickSearch.Payload.ps1
  - src/tools/QuickSearch.Payload.Encode.bat
  - src/tools/QuickSearch.Payload.Decode.bat
  - src/QuickSearch.vbs
  - src/QuickSearch.bat
  - tests/smoke-index.ps1
  - tests/smoke-text-transfer.ps1
  - tests/smoke-ultra-transfer.ps1
  - tests/smoke-payload.ps1
date: "2026-06-18"
---

# QuickSearch ADC Index

QuickSearch (QS) is a small Windows desktop search helper implemented in PowerShell. It provides a Windows Forms UI for searching mapped drive folders, previewing selected file content, opening matching files, and maintaining a TEAM quick-search path backed by a generated JSON inverted index rather than an installed database. Top-word extraction streams target files instead of splitting whole file contents in memory. The index stores filenames, paths, and generated top-word tags, not full source file text. TEAM quick search caches parsed index reads within the current process and materializes schema v2 results in a single document pass after term lookup. Content (Slow) is bounded by configurable result and file-size limits, prunes ignored folders, can reuse TEAM index document paths as candidates, defaults ALL scans to configured type roots, and optionally uses ripgrep when available. Legacy payload and text-transfer helpers are archived under `src/tools/` for manual reuse only. The project is intentionally lightweight and currently has no package manager, compiled build step, server runtime, database, or external service dependency.

## Project Background

QS exists to speed up day-to-day lookup across shared Orcas folders, especially `Orcas_Main\TSG-SOP` and `Orcas_Main\team`. Users can choose a drive letter, choose a document type, switch runtime profiles from the Settings button, open About guidance, search by filename or file content, open Index settings, re-index the TEAM folder with generated top-word tags from the Index popup while a responsive progress/cancel popup is visible, auto-expand a collapsible text/HTML/Markdown preview, highlight active search keywords in preview, and open matching files from the UI.

## Core Modules

- `src/QuickSearch.ps1`: Main Windows Forms entry script, UI shell, preview layout helpers, processing popup helpers, and autorun guard. This file dot-sources `src/QuickSearch.Support.ps1`.
- `src/QuickSearch.Support.ps1`: Support functions for config, version title formatting, path resolution, file search, About popup, and Index settings popup.
- `src/QuickSearch.Async.ps1`: Background indexing dialog helper that starts index jobs, polls status, updates progress text, supports cancel, and keeps the Windows Forms UI responsive.
- `src/QuickSearch.Preview.ps1`: Preview helper for RichTextBox text/Markdown rendering, WebBrowser HTML rendering, Markdown files with HTML tags, and active search keyword highlighting.
- `src/QuickSearch.Profile.ps1`: Selectable profile helper that discovers `src/profiles/*.profile.json`, defaults to `default.profile.json`, applies profile overlays to runtime config, persists the chosen profile name, and shows the Profile Settings popup.
- `src/QuickSearch.IndexStatus.ps1`: Lightweight status writer used by index rebuilds to report scan/index/write progress to the UI.
- `src/QuickSearch.IndexPolicy.ps1`: Index policy helper for `AllowedFileExtNames` extension whitelist handling and configurable tag extraction limits, including `MaxTagFileSizeMB` handling for new or changed large files.
- `src/QuickSearch.IndexResume.ps1`: Resumable index checkpoint helper that writes `src/data/index.json.tmp`, reads interrupted checkpoint data as a reuse source, and completes the final index replacement safely.
- `src/QuickSearch.Index.ps1`: TEAM index module that writes `src/data/index.json` schema v2 with `documents` and inverted `terms`, streams target files for top-word extraction, reuses unchanged file metadata during rebuilds, caches parsed index reads, materializes schema v2 search results in a single document pass, writes progress status, and keeps legacy schema search compatibility.
- `src/QuickSearch.Search.ps1`: Filesystem search helper used by the UI and background search job for filename and file-content searches, including `MaxSearchResults`, `MaxContentScanFileSizeMB`, ignored-folder pruning, TEAM index candidate reuse, scan-scope roots, and optional ripgrep acceleration with PowerShell fallback.
- `src/tools/QuickSearch.TextTransfer.ps1`: Archived command-line utility that compresses files or folders into ZIP bytes, writes Base64 text for text-only transfer, can split oversized output when explicitly used, and decodes/extracts the payload on the destination computer.
- `src/tools/QuickSearch.UltraTransfer.ps1`: Archived PowerShell 7+ command-line utility that packs files into a stored ZIP container, Brotli-compresses the binary container, converts it to Base64 text, and can split output when explicitly used.
- `src/tools/QuickSearch.Payload.ps1`: Archived PowerShell 7+ command-line utility that minifies QS PowerShell source, encodes it as UTF-8, compresses it with Brotli, writes Base64 text, and decodes the payload back to minified source.
- `src/tools/QuickSearch.Payload.Encode.bat`: Archived double-click payload encode launcher retained for manual reuse.
- `src/tools/QuickSearch.Payload.Decode.bat`: Archived double-click payload decode launcher retained for manual reuse.
- `src/settings/config.json` and `src/profiles/*.profile.json`: Local defaults for version, selected profile name, title, dimensions, mapped-drive paths, search types, allowed/ignored folder/file hints, tag count settings, tag extraction limits, and Content (Slow) performance settings. `default.profile.json` is the default profile.
- `src/data/index.sample.json`: Schema v2 sample index file for reference; runtime rebuilds still write generated data to `src/data/index.json`.
- `src/QuickSearch.vbs`: No-console Windows Script Host launcher that starts `src/QuickSearch.ps1` through hidden PowerShell so only the Windows Forms UI is shown.
- `src/QuickSearch.bat`: Compatibility batch launcher that delegates to `src/QuickSearch.vbs`; batch files may still briefly show a `cmd.exe` window when double-clicked.
- `tests/smoke-index.ps1`: Non-GUI smoke test for TEAM index generation, ignored-file filtering, generated tags, and indexed lookup.
- `tests/smoke-text-transfer.ps1`: Non-GUI smoke test for ZIP/Base64 encode, decode, restore, and safe extraction checks.
- `tests/smoke-ultra-transfer.ps1`: PowerShell 7+ smoke test for high-compression Brotli/Base64 transfer, minimal split files, decode round trips, and 25000-character-safe outputs.
- `tests/smoke-payload.ps1`: PowerShell 7+ smoke test for minify, UTF-8, Brotli, Base64, and decode round trips.

## Required ADC Integration

QS follows ADC 1.1.27 project-context governance. When ContextGraph project credentials are configured, project change information must be aggregated into CGA through CGA-Relay. This includes indexing, change summaries, progress updates, validation evidence, release events, blockers, risks, and related PR/PBI metadata.

Required local ADC integration points:

- CGA MCP profile: `.adc/cga-relay/mcp/mcp-servers.json`
- Operational scratchpad: `.adc/cga-relay/scratchpad/session.md`
- Project planning: `.adc/planning/`
- Project standards: `.adc/standards/`
- Durable knowledge and diagrams: `.adc/knowledge/`

Fallback MCP/API paths may document relay outages, but they do not count as official completion for project change aggregation.

## Environment Requirements

- Windows with PowerShell and .NET Windows Forms support.
- PowerShell 7+ is required only for archived Brotli helper tools under `src/tools/`.
- Access to the configured mapped drive paths.
- Execution policy that allows running local scripts, typically with `PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\QuickSearch.ps1`.
- No Node.js, Python, Docker, Redis, PostgreSQL, or web server is required for the current QS runtime.

## Current Boundaries

- Keep current runtime files under `src/`; do not move or rename `src/QuickSearch.ps1` during ADC onboarding.
- Treat generated `index.json` files as runtime artifacts unless a maintainer explicitly promotes a fixture or sample into documentation.
- Do not assume ADC web-application defaults apply to QS. FastAPI, PostgreSQL, `pgvector`, Docker, and browser validation are only relevant if QS later becomes a web or service project.
