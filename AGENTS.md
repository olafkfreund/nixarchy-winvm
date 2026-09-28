# Repository instructions

This repository is an Omarchy Quattro plugin for managing the host's Windows
VM. Keep the plugin small, keyboard-first, and compatible with Omarchy's
long-running Quickshell process.

## Plugin contract

- This plugin is menu-only. Do not add a `bar-widget` kind, top-panel entry,
  bar section, or second Quickshell process.
- `manifest.json` must declare the `menu` kind and map
  `entryPoints.menu` to `Menu.qml`.
- `Menu.qml` is a fullscreen menu surface summoned by Omarchy. It must expose
  `open(payloadJson)`, `close()`, `toggle()`, and `opened`, target the focused
  screen, use an exclusive keyboard layer, and close on Escape or outside
  click.
- Reuse `WinVmService.qml`, `winvm-launcher.sh`, and `winvm-stats.sh` for VM
  behavior. Keep credentials and certificate checks in the launcher; do not
  move secrets into QML or manifest settings.
- QML imports come from the installed Omarchy shell. Prefer `qs.Commons` and
  `qs.Ui` theme primitives over custom colors or controls.

## Keyboard behavior

The menu is driven without a mouse. Keep the existing single-key actions
stable: `L` attach/launch keep-alive, `A` launch auto-stop, `W` web console,
`F` shared folder, `S` stop, `R` refresh, and `Esc` close. Do not make a
background polling action steal focus.

## Validation

Run the smallest applicable checks before handoff:

```sh
omarchy plugin validate .
qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" \
  Menu.qml WinVmService.qml
bash -n winvm-launcher.sh winvm-stats.sh dev/sync
```

For local runtime testing, use `./dev/sync` only after validation. It copies
the plugin into `~/.config/omarchy/plugins/` and restarts the shell.

## Change discipline

- Use the repository's existing shell commands and QML patterns before adding
  dependencies or abstractions.
- Do not add a top-panel fallback or speculative configuration.
- Keep external commands explicit and preserve input validation, privilege
  boundaries, and error handling.
- Follow the repository task artifacts in `intent/`, `spec/`, and `plan/` for
  multi-file changes. Do not implement before the approved plan.
