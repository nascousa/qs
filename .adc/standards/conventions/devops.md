# DevOps and Release Conventions

QS is a local PowerShell desktop utility with no Docker, database, web server, cloud deployment, or CI/CD requirement.

## Rules

- Do not add Docker, CI/CD, installers, or cloud deployment files unless explicitly requested.
- If Docker is ever introduced, use the local Docker daemon with plain `docker` commands.
- Do not run QS release, publish, payload packaging, or split-transfer workflows unless a maintainer explicitly asks for that workflow.
- Legacy payload, ZIP/Base64, and UltraTransfer helpers are archived under `src/tools/` for manual reuse only.
- If a release or publish workflow is explicitly requested later, update version numbers and README date before packaging.
- Generated runtime data must not be packaged unless the release intentionally includes a prebuilt local index.
- Validate script parsing and JSON parsing before any explicitly requested packaging.

## ContextGraph/CGA

- Register QS in CGA when credentials are available.
- Use CGA-Relay for official change aggregation.
- Record indexing, change summaries, progress, validation evidence, release events, blockers, and risks through CGA-Relay.
