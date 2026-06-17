# Observability Conventions

QS currently uses console output and UI status text for runtime feedback.

## Rules

- Keep console messages concise and actionable.
- Include operation names such as search, index, preview, or open file.
- Include paths only when needed for local troubleshooting.
- Never log credentials, tokens, personal paths beyond what is needed for troubleshooting, or raw private document content.
- For errors, report the failing operation and safe reason without dumping sensitive file contents.
- Keep status messages actionable for long-running scans.
- Record validation summaries and notable issues in `.adc/cga-relay/scratchpad/session.md` for substantial changes.

## Future Option

If file logging is added, write logs under `logs/` or `tmp/`, keep them ignored, rotate or limit size, and redact private data by default.
