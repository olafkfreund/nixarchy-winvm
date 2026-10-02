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

## libvirt/KVM

Besides the containerized VM, the plugin can control a libvirt/KVM Windows
domain. The launcher picks the backend in this order:

1. dockur, if `omarchy-windows-vm` is on `PATH` and its `docker-compose.yml`
   exists (`/var/lib/omarchy/windows` or `~/.config/windows`);
2. the `DOMAIN` from `~/.config/windows/libvirt.conf`, if `virsh dominfo`
   finds it;
3. the single domain that libosinfo tags as Windows (virt-manager does this).
   Zero or several matches show a message in the menu and nothing runs.

```ini
# ~/.config/windows/libvirt.conf (both keys optional; no inline comments)
# DOMAIN: letters, digits, . _ - (max 64)
DOMAIN=win11
# URI: qemu:///system (default) or qemu:///session
URI=qemu:///system
```

Invalid values are ignored. For libvirt, <kbd>L</kbd> starts the domain if
needed and opens `virt-viewer`, <kbd>A</kbd> shuts the domain down when the
viewer closes, and <kbd>S</kbd> requests a graceful shutdown (never a forced
power-off). <kbd>W</kbd> and <kbd>F</kbd> are dockur-only and ignored.

Requires `virsh` and `virt-viewer`, plus libvirt access (the `libvirtd` group
for `qemu:///system`). Check what was detected with:

```bash
./winvm-launcher.sh backend
```

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
bash -n winvm-launcher.sh winvm-stats.sh dev/sync dev/test-launcher
bash dev/test-launcher
```

For the complete disposable VM installation and UI-testing workflow, see
[`docs/vm-testing.md`](docs/vm-testing.md).

## Remove

```bash
omarchy plugin remove nixarchy.winvm
```

## License

MIT
