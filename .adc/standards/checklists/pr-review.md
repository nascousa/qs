# PR Review Checklist

Use this checklist for QS reviews and local preflight checks.

- ADC context loaded from `.adc/index.md` and `.adc/prompt-rules.md`.
- README version/date reviewed and updated as needed.
- No secrets, tokens, private keys, personal credentials, or private file contents are committed.
- Generated indexes and runtime outputs are excluded unless intentionally included.
- PowerShell scripts parse successfully after changes.
- JSON config files parse with `ConvertFrom-Json`.
- PowerShell syntax and cmdlet names are reviewed.
- Path handling is validated for mapped-drive, no-result, missing-index, and invalid-selection cases.
- UI changes do not overlap controls or make long paths unreadable.
- Functional changes include either automated tests or documented manual smoke evidence.
- Architecture and data-flow diagrams are updated when behavior or structure changes.
- CGA-Relay activity/indexing is recorded when ContextGraph credentials are configured.
