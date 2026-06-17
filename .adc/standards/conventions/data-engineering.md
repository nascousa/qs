# Data and Configuration Conventions

QS uses JSON files for configuration and generated indexes. Search target files live outside the repository on mapped drives.

## Canonical Files

- `src/settings/config.json`: Main version source, UI defaults, search type list, mapped-drive path templates, allowed/ignored file settings, tag indexing settings, and tag extraction limits such as `AllowedFileExtNames` and `MaxTagFileSizeMB`.
- `src/profiles/*.profile.json`: Selectable local profile overlays. `default.profile.json` is the default profile, and `src/settings/config.json` `ProfileName` stores the selected profile file name.
- `src/data/index.json`: Generated TEAM file index if the re-index action is used; schema v2 includes document metadata, generated tags, tag counts, and an inverted terms table.
- `src/data/index.json.tmp`: Resumable TEAM index checkpoint written during rebuilds and replaced into `index.json` only after completion.
- `src/data/index.sample.json`: Static schema v2 sample index file for reference and smoke validation.

## Rules

- Keep JSON valid and parseable by `ConvertFrom-Json`.
- Keep profile file names under `src/profiles/` and use the `*.profile.json` naming convention for selectable profiles.
- Use stable property names for generated indexes.
- Treat generated index files as derived data unless explicitly promoted to fixtures.
- Do not store private document contents in generated indexes.
- Store generated top-word metadata only; do not persist full source file text in `src/data/index.json`.
- Treat `AllowedFileExtNames` as an index file extension whitelist when it is non-empty; files outside the whitelist should be skipped before content reads.
- Use `src/data/index.json.tmp` as resumable checkpoint data during long index rebuilds; do not delete it after interrupted indexing.
- Reuse unchanged file document metadata when size and timestamp match, and only extract tags for new or changed files.
- Generate top-word metadata with streaming reads so large source files do not require a full-file string or full split-word array in memory.
- New or changed files larger than `MaxTagFileSizeMB` should skip generated tag extraction while remaining searchable by filename and path.
- Keep local machine paths configurable rather than hardcoded when changing behavior.
- Do not introduce PostgreSQL, Redis, vector stores, or graph databases for QS unless the task explicitly requests a larger architecture change.
- If semantic search is later approved, document the retrieval design before implementation.

## Suggested Index Schema

Generated file indexes use schema v2 with stable top-level `documents` and `terms` properties:

```json
{
  "schemaVersion": 2,
  "root": "S:\\Orcas_Main\\team",
  "createdUtc": "2026-06-16T00:00:00.0000000Z",
  "documents": [
    {
      "id": 1,
      "name": "example.txt",
      "path": "S:\\Orcas_Main\\team\\example.txt",
      "sizeInBytes": 1234,
      "lastModified": "2026-06-15T00:00:00.0000000-07:00",
      "lastWriteUtc": "2026-06-15T07:00:00.0000000Z",
      "tags": ["example", "search"],
      "tagCounts": {
        "example": 4,
        "search": 2
      }
    }
  ],
  "terms": {
    "example": [1],
    "search": [1]
  }
}
```

Legacy array-shaped indexes remain readable for search compatibility, but new writes should use schema v2.
