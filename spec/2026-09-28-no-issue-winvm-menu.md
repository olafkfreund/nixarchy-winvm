---
status: draft
issue: 1
intent: intent/2026-09-28-no-issue-winvm-menu.md
---

# Spec: Convert Windows VM controls to an Omarchy menu popout

## Design

- Change `manifest.json` from a `bar-widget` plugin to a menu-only plugin:
  `kinds: ["menu"]` and `entryPoints.menu: "Menu.qml"`. Remove bar-only
  configuration and registration metadata.
- Replace the bar/panel entry flow with `Menu.qml`, following the working
  Omarchy menu contract used by the installed local plugins:
  `shell`, `manifest`, `opened`, focused-screen selection, `open(payloadJson)`,
  `close()`, and `toggle()`.
- Render the existing Windows VM controls in a fullscreen transparent
  `PanelWindow` with a menu scrim and centered `BorderSurface`. Use
  `WlrLayershell.Overlay` and `WlrKeyboardFocus.Exclusive` so the menu owns
  keyboard input while open and closes on Escape or outside click.
- Keep `WinVmService.qml`, `winvm-launcher.sh`, and `winvm-stats.sh` as the
  service boundary. Adapt the existing panel content into the menu with the
  same keyboard actions: `L`, `A`, `W`, `F`, `S`, `R`, and `Esc`.
- Remove `BarWidget.qml` and the unused bar-specific `Panel.qml` so the plugin
  cannot be installed as a top-panel widget. Update `dev/sync` and `README.md`
  for menu-only installation and validation.
- Do not add dependencies, a second Quickshell process, or a new service
  abstraction.

## Alternatives rejected

- Keep both menu and bar entry points: rejected because the requested UX is
  menu-only and retaining the bar creates an unnecessary top-panel surface.
- Keep the existing `Panel` as the menu entry point: rejected because Omarchy
  `menu` plugins are fullscreen summoned surfaces and need the menu lifecycle,
  focused-screen targeting, and exclusive keyboard layer.
- Start a separate Quickshell process: rejected by Omarchy's plugin contract;
  plugins share the long-running shell process.

## Risks

- QML API or import mismatches against the installed Omarchy shell can prevent
  the menu from loading.
- Removing the bar entry point changes discovery and local sync behavior for
  existing installations.
- The menu surface can intercept all keyboard input while open; Escape and
  outside-click handling must remain reliable.
- VM launch, stop, credential, and certificate behavior must not regress while
  moving only the UI host.

## Verification

- `omarchy plugin validate .`
- `qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" Menu.qml WinVmService.qml`
- `bash -n winvm-launcher.sh winvm-stats.sh dev/sync`
- Local runtime check through `./dev/sync`: plugin appears as a menu, does not
  add a bar widget, opens from the Omarchy menu, receives keyboard focus, runs
  each shortcut, and closes with Escape and outside click.
