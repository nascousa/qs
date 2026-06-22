# Data and Configuration Conventions

QS uses JSON files for configuration and generated indexes. Search target files live outside the repository on mapped drives.

## Canonical Files

- `src/settings/config.json`: Main version source, UI defaults, search type list, mapped-drive path templates, allowed/ignored file settings, tag indexing settings, and tag extraction limits such as `AllowedFileExtNames` and `MaxTagFileSizeMB`.
- `src/profiles/*.profile.json`: Selectable local profile overlays. `default.profile.json` is the default profile, and `src/settings/config.json` `ProfileName` stores the selected profile file name.
- `src/data/index.json`: Generated TEAM file index manifest if the re-index action is used; schema v3 points to document and term shard files under `src/data/index-shards/`.
- `src/data/index-shards/`: Generated schema v3 document and term shard files used by TEAM quick search to avoid parsing one large JSON file.
- `src/data/index.json.tmp`: Resumable TEAM index checkpoint written during rebuilds and replaced into `index.json` only after completion.
- `src/data/index.sample.json`: Static schema v2 sample index file for reference and smoke validation.

## Rules

- Keep JSON valid and parseable by `ConvertFrom-Json`.
- Keep profile file names under `src/profiles/` and use the `*.profile.json` naming convention for selectable profiles.
- Use stable property names for generated indexes.
- Treat generated index files as derived data unless explicitly promoted to fixtures.
- Do not store private document contents in generated indexes.
- Store generated top-word metadata only; do not persist full source file text in `src/data/index.json` or `src/data/index-shards/`.
- Treat `AllowedFileExtNames` as an index file extension whitelist when it is non-empty; files outside the whitelist should be skipped before content reads.
- Use `src/data/index.json.tmp` as resumable checkpoint data during long index rebuilds; do not delete it after interrupted indexing.
- Reuse unchanged file document metadata when size and timestamp match, and only extract tags for new or changed files.
- Generate top-word metadata with streaming reads so large source files do not require a full-file string or full split-word array in memory.
- New or changed files larger than `MaxTagFileSizeMB` should skip generated tag extraction while remaining searchable by filename and path.
- Keep local machine paths configurable rather than hardcoded when changing behavior.
- Do not introduce PostgreSQL, Redis, vector stores, or graph databases for QS unless the task explicitly requests a larger architecture change.
- If semantic search is later approved, document the retrieval design before implementation.

## Suggested Index Schema

Generated file indexes use schema v3 with a stable manifest plus document and term shard files:

```json
{
  "schemaVersion": 3,
  "indexFormat": "QuickSearch.ShardedIndex",
  "root": "S:\\Orcas_Main\\team",
  "createdUtc": "2026-06-16T00:00:00.0000000Z",
  "complete": true,
  "documentCount": 1,
  "termCount": 2,
  "documentShardSize": 1000,
  "shardDirectory": "index-shards",
  "documentShards": [
    {
      "key": "0000",
      "file": "documents-0000.json",
      "startId": 1,
      "endId": 1,
      "count": 1
    }
  ],
  "termShards": [
    {
      "key": "e",
      "file": "terms-e.json",
      "count": 1
    }
  ]
}
```

Legacy array-shaped and schema v2 indexes remain readable for search compatibility, but new writes should use schema v3 shards.
