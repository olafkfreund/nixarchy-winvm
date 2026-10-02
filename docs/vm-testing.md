# Testing in a Nixarchy VM

UI work must be tested in a disposable Nixarchy guest. Do not enable the
plugin or restart the long-running host Quickshell session while iterating.

## One-time setup

The project shell supplies `devenv`, `qmllint`, QEMU, OVMF, `7z`, and `gh`:

```sh
devenv allow
devenv shell -- validate
```

The VM state lives outside the repository:

```text
~/.local/share/nixarchy-winvm/nixarchy-try/
```

The directory contains the qcow2 disk, UEFI variables, and the extracted
installer kernel/initrd. These files are runtime state, not source code.

## Unattended install

Use the Nixarchy unattended-install contract from the
[manual](https://olafkfreund.github.io/nixarchy/manual/unattended-installs):
an answers file is passed as `nixarchy.answers=...` on the installer kernel
command line. The project command does the following:

1. Creates a temporary secret HTTPS gist containing the parsed `key=value`
   answers. Plain HTTP is intentionally rejected by the installer.
2. Builds or downloads the Nixarchy network ISO.
3. Extracts the ISO's kernel and initrd because this QEMU rejects `-append`
   unless `-kernel` is also supplied.
4. Creates a fresh 32 GiB qcow2 disk and UEFI variable file.
5. Boots QEMU with KVM when available, otherwise software emulation.
6. Deletes the temporary gist when QEMU exits.

The current disposable test account is `demo` / `demo`:

```sh
VM_FRESH=1 devenv shell -- vm-install-unattended
```

`VM_FRESH=1` is required before replacing existing VM state. Without it, the
command refuses to guess whether an existing disk is valuable.

After the installer powers off, boot the installed guest through the guest-only
control interface:

```sh
devenv shell -- vm-boot-controlled
```

This launcher uses QMP, a visible GTK guest display by default, and a
read-only 9p repository share. The GTK window is observation-only: the agent
never focuses or moves it. Set `WINVM_DISPLAY=none` for headless runs. Capture
the guest display and send guest keyboard input with:

```sh
devenv shell -- vm-qmp screendump /tmp/winvm.ppm
devenv shell -- vm-qmp key ctrl-alt-f2
devenv shell -- vm-qmp type demo
```

Do not use host `ydotool`, `wtype`, Hyprland dispatch, or host screenshots for
guest testing.

The controlled launcher forwards guest SSH to localhost port `2222`. The
installed guest must enable it declaratively in
`/etc/nixos/hosts/nixarchy-winvm/configuration.nix`:

```nix
services.openssh.enable = true;
services.openssh.settings.PasswordAuthentication = true;
```

Run `sudo nixos-rebuild switch` in the guest after adding those options. This
is the procedure verified against the current `demo`/`demo` VM; it survives a
guest reboot, but a fresh unattended install must repeat it.

Then use:

```sh
ssh -p 2222 demo@127.0.0.1
scp -P 2222 -r . demo@127.0.0.1:/tmp/nixarchy-winvm
sshfs -p 2222 demo@127.0.0.1:/home/demo /tmp/nixarchy-guest-home
```

Use SSH/SCP/SSHFS for deployment and inspection after the rebuild. QMP remains
the fallback for login, display capture, and the one-time guest configuration.

The guest also includes `ai-mirror`. Run it through SSH with the guest's
graphical-session variables, not the host's:

```sh
sig=$(ssh -p 2222 demo@127.0.0.1 'hyprctl instances -j | jq -r ".[0].instance"')
ssh -p 2222 demo@127.0.0.1 \
  "HYPRLAND_INSTANCE_SIGNATURE=$sig XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 ai-mirror windows"
ssh -p 2222 demo@127.0.0.1 \
  "HYPRLAND_INSTANCE_SIGNATURE=$sig XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 ai-mirror control agent"
```

Use `omarchy-shell shell toggle nixarchy.winvm` to summon the plugin and
`ai-mirror screenshot --output Virtual-1 --out /tmp/menu.png` to capture the
guest display. The required ai-mirror fix is commit `49de649` or newer: a
layer may close after key-down, so its matching key-up must still be released
without revalidating the now-gone surface. Release guest ai-mirror control
with `ai-mirror control off` when finished.

The tested VM pins that branch declaratively by adding an `ai-mirror` input to
`/etc/nixos/flake.nix`, setting `nixarchy.inputs.ai-mirror.follows =
"ai-mirror"`, updating `flake.lock`, and running `sudo nixos-rebuild switch`.
Repeat this after a fresh VM install until the fix is merged into the normal
Nixarchy input.

## Reusable plugin install flow

Prefer SSH/SCP for the plugin files. From the repository root, use:

```sh
scp -P 2222 -r . demo@127.0.0.1:/tmp/nixarchy-winvm
ssh -p 2222 demo@127.0.0.1 \
  'mkdir -p /home/demo/.config/omarchy/plugins/nixarchy.winvm && cp -r /tmp/nixarchy-winvm/. /home/demo/.config/omarchy/plugins/nixarchy.winvm/'
```

If SSH is not yet available, keep `vm-boot-controlled` attached in one
terminal and use the QMP fallback from a second terminal:

```sh
devenv shell -- vm-qmp key meta_l-ret
devenv shell -- vm-qmp type 'git clone https://github.com/olafkfreund/nixarchy-winvm.git /tmp/nixarchy-winvm'
devenv shell -- vm-qmp key ret
devenv shell -- vm-qmp type 'mkdir -p /home/demo/.config/omarchy/plugins/nixarchy.winvm'
devenv shell -- vm-qmp key ret
devenv shell -- vm-qmp type 'cp -r /tmp/nixarchy-winvm/. /home/demo/.config/omarchy/plugins/nixarchy.winvm/'
devenv shell -- vm-qmp key ret
```

Use the guest terminal for validation and enabling, then capture checkpoints
without touching the host desktop:

```sh
devenv shell -- vm-qmp screendump /tmp/winvm.ppm
```

`vm-qmp type` accepts a deliberately small ASCII subset. Add a character
mapping in `dev/vm-qmp.py` before using another shell character; never fall
back to host typing tools.

Stop it with:

```sh
devenv shell -- vm-stop
```

## Why the first approach was wrong

`nix run github:olafkfreund/nixarchy#try` is the interactive wizard path. It
does not accept an answer URL and must not be used when a reproducible test
user is required. Upstream's `#installer-vm` has baked-in test answers for
`omarchy`; it is useful for upstream installer testing but does not create the
requested `demo` account without overriding its NixOS module.

The supported custom path is the release ISO plus `nixarchy.answers`. The
answers file contains a plaintext password by design, so it must be transient,
HTTPS-only, and deleted after the installer reads it. Never commit it or put it
in a normal repository file.

## Useful checks

```sh
ps -eo pid=,args= | rg 'qemu-system-x86_64.*nixarchy-try'
qemu-img info ~/.local/share/nixarchy-winvm/nixarchy-try/nixarchy-try.qcow2
git status --short
```

Do not inspect or copy the qcow2 while QEMU has it open; QEMU's write lock is
the protection against corrupting an active guest.
