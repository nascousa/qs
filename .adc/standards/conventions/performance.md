# Performance Conventions

## Search Performance

- Prefer filename or index-backed search for large mapped drives.
- Treat full content search as expensive and keep the UI status visible while it runs.
- Avoid unbounded `Get-ChildItem -Recurse | Select-String` scans unless the user explicitly chooses slow content search.
- Use `-File` for file scans when directories should not be processed.
- Bound future indexing or scanning work by explicit roots from configuration.
- Add cancellation or background-worker behavior before making long searches the default path.

## UI Responsiveness

- Do not load very large files fully into the preview pane.
- Cap preview size and show a clear status when content is truncated.
- Avoid blocking the Windows Forms UI thread for long indexing operations in future changes.

## Generated Indexes

- Generated indexes should have a stable schema and be reproducible from source folders.
- Index generation should skip ignored files and extensions early.
- Do not repeatedly rebuild indexes when a cached index is valid for the selected folder.
- TEAM quick search should prefer the schema v2 inverted `terms` table over linearly scanning every document entry.
- Re-indexing may reuse unchanged file tag metadata when size and timestamps still match.
- Top-word extraction should stream target files through a bounded buffer instead of reading entire files and splitting all words into memory.
- Large generated indexes should remain outside prompt/context loading unless needed for a specific task.
