---
status: approved
issue: 6
intent: intent/2026-11-19-6-no-keeploaded.md
---

# Spec: load the menu view on first open (drop keepLoaded)

Part of olafkfreund/nixos_config#3107. The full, reviewed spec is
[spec/2026-11-19-3107-shell-startup.md][full] in nixos_config; this record
carries the part that applies to `nixarchy.winvm`.

[full]: https://github.com/olafkfreund/nixos_config/blob/perf/3107-shell-startup/spec/2026-11-19-3107-shell-startup.md

## Design

Remove `keepLoaded` from `manifest.json`; update the comments and checks
that assert it. Safe because VM actions use execDetached; only a status
poll lives in the view, and every caller uses `shell toggle` (directly or
via `nixarchy-plugin`), which loads the view on demand.

## Risks

The first open per session compiles the view cold. See the PR for the
plugin's small losses.

## Verification

`jq -e 'has("keepLoaded")|not' manifest.json`; the repo's flake checks.
