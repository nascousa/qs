# Environment Bootstrap Guide

Use these exact commands and checks for QS. Do not guess alternate startup commands.

## Prerequisites

- Windows desktop session.
- Windows PowerShell or PowerShell capable of loading `System.Windows.Forms`.
- Access to the mapped drive selected in the UI.
- No Node.js, Python, Docker, Redis, PostgreSQL, or web server is required for the current QS application.

## Run QS

```powershell
Set-Location D:\Repos\QuickSearch
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\QuickSearch.ps1
```

For a no-console UI launch, use the Windows Script Host launcher:

```cmd
src\QuickSearch.vbs
```

The Windows batch launcher is kept for compatibility and delegates to the VBS launcher, but a batch file may still briefly show `cmd.exe` when double-clicked:

```cmd
src\QuickSearch.bat
```

For debugging with a visible console that remains open after the UI closes:

```powershell
Set-Location D:\Repos\QuickSearch
$env:QS_PAUSE_ON_EXIT = '1'
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\QuickSearch.ps1
```

## Parse-Only Validation

Use this before and after PowerShell script changes:

```powershell
Set-Location D:\Repos\QuickSearch
Get-ChildItem -LiteralPath .\src -Recurse -File -Filter 'QuickSearch*.ps1' | ForEach-Object { [scriptblock]::Create((Get-Content -LiteralPath $_.FullName -Raw)) | Out-Null }
Get-Content -LiteralPath .\src\settings\config.json -Raw | ConvertFrom-Json | Out-Null
Get-ChildItem -LiteralPath .\src\profiles -File -Filter '*.profile.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null }
Get-Content -LiteralPath .\.adc\cga-relay\mcp\mcp-servers.json -Raw | ConvertFrom-Json | Out-Null
```

## Non-GUI Smoke Test

Use this to validate integrated TEAM index generation and tag lookup without mapped drives or Windows Forms UI:

```powershell
Set-Location D:\Repos\QuickSearch
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke-index.ps1
```

Run archived helper smoke tests only when changing files under `src/tools/`:

```powershell
Set-Location D:\Repos\QuickSearch
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke-text-transfer.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke-ultra-transfer.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke-payload.ps1
```

## Manual UI Smoke Check

1. Start `src/QuickSearch.ps1`.
2. Start `src\QuickSearch.vbs` and confirm it opens the same UI without a companion console window.
3. Start `src\QuickSearch.bat` and confirm it delegates to the VBS launcher.
4. Confirm the window title and layout load from `src/settings/config.json`.
5. Open `Settings`, confirm `default.profile.json` is selected by default, choose another available profile if needed, and apply it.
6. Select a drive letter that is actually mapped on the machine.
7. Run one filename search against a small folder or test fixture first.
8. Use `Re-Index Team Folder` on a small accessible TEAM folder and confirm the indexing popup shows stage, file counts, reused count, current file name, elapsed time, and a Cancel button before `src/data/index.json` is regenerated.
9. Open `TagManager`, confirm the settings popup shows TEAM path, top words per file, ignored filenames, allowed extensions, ignored extensions, and ignored folders.
10. Use TagManager `Rebuild Index` on a small accessible TEAM folder and confirm the indexing progress popup appears.
11. Save settings only when the displayed path and ignore lists are intended.
12. Run one TEAM quick search that matches a filename or generated tag.
13. Confirm the preview pane is collapsed before a file is selected and the results list uses the available width.
14. Select a plaintext result and confirm the preview pane auto-expands without freezing the UI.
15. Use `Hide Preview` and `Show Preview` to confirm manual preview toggling works.
16. Select a Markdown result and confirm headings, lists, quotes, code, bold, and italic text render in the preview pane.
17. Select an HTML result, or a Markdown result that contains HTML tags, and confirm it renders in the preview pane.
18. Run a search, select a matching result whose file body contains the search keyword, and confirm the keyword is highlighted in the preview pane.
19. Open a selected file only when the target path is expected.

## ContextGraph Services Integration

When CGA is available, register QS in the local CGA Admin UI and set credentials through environment variables only:

```powershell
$env:CONTEXTGRAPH_MCP_SERVER_URL = "http://localhost:18001/mcp/sse"
$env:CONTEXTGRAPH_BRIEFING_API_URL = "http://localhost:18001/api/project/work-briefing/activity"
$env:CONTEXTGRAPH_INDEXING_POLICY = "auto-incremental"
$env:CONTEXTGRAPH_MCP_TOKEN = "<token-from-cga-admin>"
$env:CONTEXTGRAPH_PROJECT_ID = "<project-id-from-cga-admin>"
```

After CGA-Relay and the CGA MCP Server profile are configured:

1. Confirm `.adc/cga-relay/mcp/mcp-servers.json` contains `cga-mcp-server`.
2. Run a one-time full-project index for tracked source, documentation, configuration, and ADC files.
3. For later work, use incremental indexing for changed files.
4. Record change summaries, progress, validation evidence, release events, blockers, and risks through CGA-Relay.

Do not write real CGA tokens or project credentials into `.env`, Markdown, JSON, or scripts.
