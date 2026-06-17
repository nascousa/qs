# ADR 001: Keep PowerShell Windows Forms Baseline

## Status

Accepted

## Context

QS is currently a low-friction Windows desktop utility. Its users can launch it directly from PowerShell without package installation, a local web server, Docker, or database services.

## Decision

Keep the current PowerShell Windows Forms baseline during ADC onboarding. Do not migrate QS into a web application or service architecture unless a future task explicitly approves that direction.

## Consequences

- ADC onboarding documents the legacy layout instead of forcing a `src/` migration.
- Future stabilization should first add tests around existing behavior.
- UI validation remains manual until a suitable desktop automation strategy is adopted.
