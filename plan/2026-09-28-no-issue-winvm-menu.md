---
status: approved
issue: 1
spec: spec/2026-09-28-no-issue-winvm-menu.md
---

# Plan: Convert Windows VM controls to an Omarchy menu popout

The approved design converts `nixarchy.winvm` into a menu-only
Omarchy plugin. `Menu.qml` will own a fullscreen, focused-screen, exclusive
keyboard surface; `WinVmService.qml` and the existing launcher/stat scripts
remain unchanged service boundaries. The bar widget and nested bar panel are
removed so no top-panel surface remains.

## Steps

1. `manifest.json`: declare only the `menu` kind and `entryPoints.menu` mapped
   to `Menu.qml`; retain only settings needed by the menu → verify JSON parses
   and the menu entry file exists.
2. `Menu.qml`: adapt the existing Windows VM panel content into the installed
   Omarchy menu lifecycle with focused-screen selection, scrim/card layout,
   exclusive overlay keyboard focus, outside-click/Escape close, and the
   existing `WinVmService` actions → verify the menu has `open(payloadJson)`,
   `close()`, `toggle()`, and `opened` and that all shortcuts remain mapped.
3. Delete `BarWidget.qml` and `Panel.qml`; update `dev/sync` to copy and lint
   only the menu entry plus shared service/scripts → verify no manifest,
   sync command, or docs reference a bar widget.
4. `README.md`: document menu-only installation, summon/use commands, keyboard
   controls, validation, and removal → verify commands match the final plugin
   ID and entry point.

Implementation note: the menu retains VM state, endpoint status, transition
messages, and all requested actions, but intentionally omits the old bar
panel's large resource-allocation dashboard. That dashboard was not needed for
the menu workflow and would make the summoned surface larger without adding a
requested control.

Implementation extension: the repository also provides a project-local devenv
and `nix develop` flake shell with Qt 6's `qmllint` and a single `validate`
command. This keeps the QML validator reproducible without adding a
machine-wide package.

## Tests

```sh
omarchy plugin validate .
qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" Menu.qml WinVmService.qml
bash -n winvm-launcher.sh winvm-stats.sh dev/sync
```

Then run `./dev/sync` and manually verify discovery as a `menu`, no bar icon,
menu opening and focus, `L/A/W/F/S/R`, Escape, outside click, shell reload,
and VM service behavior.

## Rollback

Revert the implementation commit on `feat/menu-quick-shell`, restore the
previous `bar-widget` manifest/entry files and sync script, then disable or
remove the menu plugin with `omarchy plugin disable` or `omarchy plugin remove`.
