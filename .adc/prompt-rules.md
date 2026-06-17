# AI Prompt Rules

## Mandatory Core Rules

- QS means QuickSearch.
- Before changing QS, read `.adc/index.md`, this file, and the convention file most relevant to the change.
- Keep repository files, comments, generated docs, and UI text in English unless the human explicitly requests another language.
- Preserve the current lightweight Windows PowerShell desktop utility shape unless the task explicitly requests a migration or rewrite.
- Do not move `src/QuickSearch.ps1` unless a dedicated migration task is approved.
- Do not introduce new third-party dependencies, installers, package managers, or services without explicit human approval.
- Do not write secrets, tokens, mapped-drive credentials, private file content, personal access tokens, or private keys into tracked files.
- Generated `index.json` files are runtime artifacts by default and should not be treated as canonical project truth.
- For every project update, keep `README.md` version and date aligned with the change.
- Do not run release, publish, payload packaging, or split-transfer workflows unless the human explicitly asks for that workflow.
- Legacy payload and text-transfer helpers live under `src/tools/` for manual reuse only.
- Use QS display version format without leading zero padding, for example `v1.4.4`; default increments advance the patch segment first, so `v1.4.4` increments to `v1.4.5` and carries to the minor segment only after patch `999`.
- When modifying behavior, write or update tests first where practical; if PowerShell test harnesses are absent, document manual verification evidence.

## PowerShell Rules

- Prefer clear, named variables and functions. Do not add one-letter variable names.
- Prefer PowerShell cmdlet names over aliases in changed scripts.
- Use `Join-Path` or structured path construction for new path logic.
- Use `-LiteralPath` for file operations when paths may contain wildcard characters.
- Escape user search text or provide an explicit regex mode before treating input as a regex pattern.
- Limit file previews and long recursive searches so the Windows Forms UI remains responsive.
- Validate path handling carefully before changing search or open-file behavior.

## ADC Standard Tracking

- The upstream ADC standard for this onboarding is `1.1.27` dated `2026-06-15`.
- Preserve QS-specific overrides in this file when syncing future ADC changes.
- When a newer upstream ADC standard is adopted, update `.adc/index.md`, `.adc/prompt-rules.md`, `.adc/bootstrap.md`, and relevant files under `.adc/planning/`, `.adc/standards/`, and `.adc/knowledge/`.
- Record ADC rule changes in `.adc/knowledge/amendments.md`.

## ContextGraph and CGA-Relay Policy

- Keep `.adc/cga-relay/mcp/mcp-servers.json` enabled as the language-agnostic CGA MCP profile.
- Inject `CONTEXTGRAPH_MCP_TOKEN` and `CONTEXTGRAPH_PROJECT_ID` through environment variables only.
- Never write ContextGraph credentials into tracked files.
- After meaningful source, documentation, configuration, or validation changes, record progress and index changed files through CGA-Relay when credentials are available.
- Document progress, failed attempts, environment issues, validation evidence, blockers, risks, and release events in `.adc/cga-relay/scratchpad/session.md` before concluding substantial work.
- ContextGraph retrieval supports analysis but does not replace local script review, validation, or tests.
- Fallback MCP/API paths may document relay outages, but they do not count as official completion for project change aggregation.

## Allowed Exceptions

- For documentation-only ADC updates, local GUI execution is not required.
- For exact single-file edits with fully known scope, bounded local reading is acceptable before ContextGraph retrieval if CGA credentials are unavailable.
