# Omarchy Windows VM

A menu-only Quickshell plugin for launching and monitoring the containerized
Windows VM on Omarchy Quattro. It adds no top-panel widget.

## Features

- Shows VM state, RDP/Web endpoint state, and transition messages.
- Launches or attaches FreeRDP, opens the web console, opens the shared folder,
  stops the VM, and refreshes status.
- Keeps RDP endpoint ownership and certificate validation in the launcher.
- Uses Omarchy's fullscreen menu with exclusive keyboard focus.

## Installation

```bash
omarchy plugin add https://github.com/olafkfreund/nixarchy-winvm.git --enable
```

Summon it from the Omarchy menu. It is a `menu` plugin and does not belong in
an `omarchy bar` section.

For local development:

```bash
./dev/sync
```

The sync script validates and enables the plugin but does not restart the
shell by default. After reviewing the result, reload explicitly with:

```bash
RESTART_SHELL=1 ./dev/sync
```

## Keyboard controls

| Key | Action |
|---|---|
| <kbd>L</kbd> | Launch the VM or attach FreeRDP |
| <kbd>A</kbd> | Launch FreeRDP and stop the VM when it closes |
| <kbd>W</kbd> | Open the web console at `127.0.0.1:8006` |
| <kbd>F</kbd> | Open the `~/Windows` shared folder |
| <kbd>S</kbd> | Stop the VM |
| <kbd>R</kbd> | Refresh status |
| <kbd>Esc</kbd> | Close the menu |

## Validation

With devenv:

```bash
devenv shell
validate
```

Or with the flake:

```bash
nix develop
qmllint --version
```

The project environment supplies Qt 6's `qmllint`; the flake is the smaller
shell-only fallback.

```bash
omarchy plugin validate .
qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" Menu.qml WinVmService.qml
bash -n winvm-launcher.sh winvm-stats.sh dev/sync
```

## Remove

```bash
omarchy plugin remove nixarchy.winvm
```

## License

MIT
