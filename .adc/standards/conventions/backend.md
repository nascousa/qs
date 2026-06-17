# PowerShell Logic Conventions

QS has no backend service. Treat PowerShell functions as the application logic layer, and do not invent a web service unless the task explicitly asks for one.

## Rules

- Keep functions small enough to test manually or with future Pester coverage.
- Prefer `param(...)` blocks for new functions.
- Use `Join-Path` for new path construction.
- Use `-LiteralPath` when reading or opening paths selected from search results.
- Avoid broad recursive scans where a narrower path or prebuilt index can serve the user.
- Avoid global state for new logic unless needed by the Windows Forms event model.
- Return structured objects from indexing functions and keep property names consistent across producers and consumers.
- Do not add FastAPI, databases, background services, or service hosting to QS unless a service architecture is explicitly approved.

## Error Handling

- Surface recoverable errors in the UI status field and console output.
- Do not crash on empty selections, missing mapped drives, missing index files, unreadable files, or invalid JSON.
- Do not log raw credentials or private file contents.
