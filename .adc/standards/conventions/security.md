# Security Conventions

## Local File Safety

- Treat mapped-drive files as potentially sensitive.
- Do not copy file contents into ADC documentation, logs, issue reports, or CGA activity summaries.
- Open files only from selected search results and validated paths.
- Validate file paths before opening files.
- Handle missing or unmapped drives without exposing machine-specific details beyond what the user needs.
- Do not add network writes or destructive file operations without explicit approval.
- Avoid recursive operations that delete, rename, or mutate searched folders.

## Input Handling

- Treat search text as user input.
- Escape regex metacharacters unless an explicit regex search mode is implemented.
- Prefer `-LiteralPath` for filesystem operations using user-selected paths.
- Fail closed when configuration JSON is invalid or required properties are missing.

## Secret Handling

- Do not commit `.env`, tokens, API keys, private keys, ContextGraph credentials, or personal mapped-drive credentials.
- Do not add real ContextGraph credentials to `.adc/cga-relay/mcp/mcp-servers.json`.
- Inject `CONTEXTGRAPH_MCP_TOKEN` and `CONTEXTGRAPH_PROJECT_ID` through environment variables only.
- Never print raw tokens or authorization headers.

## Dependency Policy

- Do not add third-party dependencies without human approval.
- If a dependency is approved later, check for known high-severity vulnerabilities before adopting it.
