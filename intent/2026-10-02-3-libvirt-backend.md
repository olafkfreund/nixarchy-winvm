---
status: approved
issue: 3
author: olafkfreund
---

# Intent: Control libvirt/KVM Windows VMs from the menu

## Problem

The plugin only drives the dockur-based `omarchy-windows-vm` container. Its
state detection, launcher, and stats all assume that backend: a root-owned
`docker-proxy` on `127.0.0.1:3389`/`8006`, `omarchy-windows-vm launch|stop`,
and a QEMU process tagged `process=windows`.

Many users run Windows as a libvirt/KVM domain instead (virt-manager,
`qemu:///system`). For them the menu always shows *Stopped*, and `L`, `A`,
`W` and `S` either fail or try to start a dockur VM that doesn't exist. The
author's own host is in this situation: no `omarchy-windows-vm` install, and a
libvirt domain `win11` (shut off, `qemu:///system`, NAT network `default`,
SPICE graphics, 20 vCPU, 24 GiB).

## Proposed outcome

A user whose Windows VM is a libvirt domain can summon the same menu and:

- see the domain's real state (running, starting, stopping, shut off) and
  basic stats (vCPU, memory, CPU use);
- start it and open its display with `L`;
- start it so it shuts down when the display is closed with `A`;
- shut it down gracefully with `S`;
- refresh with `R` and close with `Esc`, unchanged.

Dockur users see no change in behaviour.

## Affected users and systems

- Users of this plugin with a libvirt Windows domain; dockur users, who must
  not regress.
- `WinVmService.qml` (state, actions), `winvm-launcher.sh` (start/attach),
  `winvm-stats.sh` (stats), `Menu.qml` (labels and which actions are shown),
  possibly `manifest.json` settings, `README.md`.
- Host tools: `virsh` and `virt-viewer`/`remote-viewer` (present on the
  author's host via the system profile); libvirt access through the
  `libvirtd` group.

## Constraints

- Menu-only plugin; no bar widget or second Quickshell process (AGENTS.md).
- The existing single-key bindings stay stable; a key that has no meaning for
  a backend is hidden or reported, never silently remapped to something
  destructive.
- Credentials and certificate checks stay in the launcher, not in QML or
  manifest settings. Any RDP path to a libvirt guest must keep an equivalent
  trust check before credentials are sent. The dockur `docker-proxy` root
  check does not apply to a guest on a libvirt network.
- No privilege escalation by the plugin: use the libvirt connection the user
  already has access to; if access is missing, say so.
- Domain names and other settings are passed as argv, never through a shell,
  and are validated.
- No new runtime dependencies beyond `virsh` and a libvirt display viewer.
- No speculative configuration: only the settings this needs.
- Builds on the menu-only plugin in PR #2 (branch stacked on
  `feat/menu-quick-shell`).
- UI testing happens in the disposable Nixarchy VM first; the live libvirt
  test happens on the host after that (AGENTS.md).

## Open questions

Resolved at approval (2026-10-02): every suggested answer below is accepted.

1. **Backend selection:** auto-detect (use dockur if `omarchy-windows-vm` is
   configured, otherwise a libvirt domain), or an explicit setting? Suggested:
   auto-detect, plus one optional `libvirtDomain` setting for the domain name.
2. **Which domain:** a single configured domain, or a picker for several?
   Suggested: one domain; if no name is set, use the only Windows-looking
   domain, otherwise ask the user to set it.
3. **What `L` opens:** the SPICE console via `virt-viewer` (works with
   `win11` today), RDP to the guest's IP (needs RDP enabled in Windows,
   credentials, and a new trust check), or SPICE with RDP as a later step?
   Suggested: SPICE only for now.
4. **`W` web console and `F` shared folder:** these don't exist for libvirt
   by default. Hide them for libvirt, or map `W` to the console? Suggested:
   hide both.
5. **Stop semantics:** `virsh shutdown` (ACPI, graceful) only, or a force
   `destroy` fallback after a timeout? Suggested: graceful only; the user can
   press `S` again or use virt-manager.
6. **Connection URI:** `qemu:///system` only, or also `qemu:///session`?
   Suggested: `qemu:///system` default, overridable together with the domain
   setting.
