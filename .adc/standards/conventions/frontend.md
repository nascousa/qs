# Frontend and UI Conventions

QS is not a web application. Its current UI is Windows Forms created from PowerShell.

## Windows Forms Rules

- Preserve the existing Windows Forms UI unless a task explicitly requests redesign.
- Keep controls stable in size and location unless intentionally redesigning the UI.
- Keep UI labels concise and in English.
- Avoid adding visible instructional paragraphs inside the app surface.
- Ensure long paths and result strings do not resize the form or overlap controls.
- Bound preview content for large files so the UI stays responsive.
- Keep status updates clear: searching, completed, failed, or no results.
- For UI changes, manually validate the form on Windows.

## Web Defaults

ADC default web standards such as FastAPI, PostgreSQL with `pgvector`, dark-mode admin UI, Vuestic, Vanta.js, and browser-page debugging do not apply to QS unless QS is explicitly converted into a web application.
