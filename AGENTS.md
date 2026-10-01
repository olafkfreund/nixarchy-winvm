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

These tools are provided by the project environment. Use `devenv shell` or
`nix develop` before running them; `validate` is also available as a devenv
script.

## UI testing

Run Quickshell UI tests inside the Nixarchy QEMU VM, not in the host's
long-running Omarchy shell. Keep VM state under
`~/.local/share/nixarchy-winvm/nixarchy-try`, and install it unattended with
the documented `nixarchy.answers` kernel parameter:

```sh
VM_FRESH=1 devenv shell -- vm-install-unattended
devenv shell -- vm-boot-controlled
devenv shell -- vm-stop
```

`vm-boot-controlled` is the normal hands-off test path. It uses QEMU's QMP
Unix socket, a visible GTK guest display by default, and a read-only 9p share
of this repository. Set `WINVM_DISPLAY=none` for headless runs.
Use `devenv shell -- vm-qmp screendump /tmp/winvm.ppm` for guest screenshots
and `devenv shell -- vm-qmp key ...` or `type ...` for guest input. Never use
host `ydotool`, `wtype`, Hyprland dispatch, or host screenshots to drive the
guest.

The unattended answers create the disposable VM user `demo` with password
`demo`. The answer file is uploaded as a temporary HTTPS gist because the
Nixarchy installer deliberately refuses plaintext HTTP; it is deleted when the
installer process exits. The VM disk and EFI variables remain locally so
`vm-boot-controlled` starts the installed system. Its GTK window is for
observation only; use `WINVM_DISPLAY=none` when no visible window is wanted.

The interactive installer remains available as `devenv shell -- vm-install`,
but it is not the normal UI-test path. To discard an interrupted unattended
install, use `VM_FRESH=1` explicitly.

Do not enable this plugin or run `RESTART_SHELL=1 ./dev/sync` on the host while
developing UI. The VM is the disposable test target; host deployment happens
only after the VM test is complete.

For guest shell access, enable `services.openssh.enable = true` and
`services.openssh.settings.PasswordAuthentication = true` in the guest's
`/etc/nixos/hosts/nixarchy-winvm/configuration.nix`, then run
`sudo nixos-rebuild switch` in the guest. Use the forwarded port `2222` for
SSH/SCP. Do not install or enable guest services imperatively; the rebuild is
the source of truth. A fresh VM install needs this small declarative change
again.

The guest includes `ai-mirror`, but SSH does not inherit its graphical-session
environment. Set `HYPRLAND_INSTANCE_SIGNATURE` from `hyprctl instances -j`,
plus `XDG_RUNTIME_DIR=/run/user/1000` and `WAYLAND_DISPLAY=wayland-1`, before
calling guest `ai-mirror`. Never call the host ai-mirror MCP for VM input. Use
the guest copy for screenshots and menu summon. Use ai-mirror `49de649` or
newer: it releases matching key-up events when a menu closes on key-down.
Older packages need QMP for that keyboard smoke test.
The tested VM overrides its NixOS flake's `ai-mirror` input to the pushed
`fix/layer-release-input` branch and rebuilds declaratively. Repeat that
override after a fresh install until the fix lands in the normal Nixarchy
input.

For local runtime testing, use `./dev/sync` only after validation. It copies
the plugin into `~/.config/omarchy/plugins/`, waits for discovery, and skips
the shell restart unless `RESTART_SHELL=1` is explicitly set.

## Change discipline

- Use the repository's existing shell commands and QML patterns before adding
  dependencies or abstractions.
- Do not add a top-panel fallback or speculative configuration.
- Keep external commands explicit and preserve input validation, privilege
  boundaries, and error handling.
- Follow the repository task artifacts in `intent/`, `spec/`, and `plan/` for
  multi-file changes. Do not implement before the approved plan.
