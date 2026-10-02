---
status: approved
issue: 3
intent: intent/2026-10-02-3-libvirt-backend.md
---

# Spec: Control libvirt/KVM Windows VMs from the menu

## Design

The plugin gets a second backend, `libvirt`, next to the existing `dockur`
backend. The launcher owns backend choice and every VM command; QML asks the
launcher which backend is active and renders accordingly. The dockur path
keeps its current commands and checks.

### Configuration

Menu plugins receive `shell` and `manifest` from Omarchy but no user settings
(only bar widgets get a settings schema; see `shell.qml` panel loader). So the
optional settings live in a key=value file next to the existing credentials
file, in the same format:

`${XDG_CONFIG_HOME:-~/.config}/windows/libvirt.conf`

```ini
DOMAIN=win11
URI=qemu:///system
```

- `DOMAIN` must match `^[A-Za-z0-9._-]{1,64}$`; otherwise it is ignored and
  the menu reports the invalid value.
- `URI` must be exactly `qemu:///system` or `qemu:///session`; default
  `qemu:///system`.
- The file is read only by `winvm-launcher.sh`. Values reach `virsh` and
  `virt-viewer` as argv, never through a shell or `eval`.

### Backend resolution (`winvm-launcher.sh`)

A `resolve_backend` function, used by every mode:

1. **dockur** if `omarchy-windows-vm status` exits 0 (it exits 1 with "not
   configured" today).
2. Otherwise **libvirt**, if `virsh` exists and a domain is found:
   - `DOMAIN` from `libvirt.conf`, if set and valid and
     `virsh -c URI dominfo DOMAIN` succeeds;
   - else the single domain from `virsh -c URI list --all --name` whose XML
     carries a `libosinfo:os id="http://microsoft.com/win/…"` tag (what
     virt-manager writes; `win11` on the author's host has it). Zero or
     several matches → no domain.
3. Otherwise **none**.

A new launcher mode `backend` prints one JSON line for QML, e.g.
`{"backend":"libvirt","domain":"win11","uri":"qemu:///system"}` or
`{"backend":"none","reason":"several Windows domains; set DOMAIN in ~/.config/windows/libvirt.conf"}`.

### Actions (libvirt)

The existing modes keep their names and meaning; the launcher dispatches on
the backend.

| Key | Mode | libvirt behaviour |
|-----|------|-------------------|
| `L` | `rdp-keepalive` / `attach` | `virsh start` if shut off, then `virt-viewer --connect URI --attach --wait DOMAIN` |
| `A` | `rdp-autostop` | as `L`, then `virsh shutdown DOMAIN` when the viewer exits |
| `S` | new `stop` mode | `virsh shutdown DOMAIN` (graceful ACPI; no `destroy`) |
| `W`, `F` | — | hidden in the menu and ignored as keys for libvirt |
| `R`, `Esc` | — | unchanged |

`--attach` gets the display through the user's libvirt connection, so no
credentials are sent and no RDP endpoint trust check is needed. `stopVm()` in
`WinVmService.qml` moves from calling `omarchy-windows-vm stop` directly to
the launcher's `stop` mode, which keeps today's command for dockur.

If `virt-viewer` is missing, the launcher sends a `notify-send` error naming
the package and does not start the domain.

### State and stats

- `WinVmService.qml` runs `winvm-launcher.sh backend` at startup and on `R`,
  and exposes `backend`, `domain` and `backendReason`.
- For **dockur**, polling stays as it is (`ss` probe, `pgrep xfreerdp`).
- For **libvirt**, the poll runs `virsh -c URI domstate DOMAIN` instead of
  the `ss` probe. Mapping: `running` → running; `shut off` → stopped;
  `in shutdown` → stopping; anything else (`paused`, `pmsuspended`,
  `crashed`, …) → stopped, with the raw state as `statusMessage`.
  `rdpClientRunning` becomes "a `virt-viewer` for this domain is running".
- `winvm-stats.sh` takes the QEMU match pattern from its first argument:
  QML passes `process=windows` for dockur (today's pattern) and
  `-name guest=DOMAIN,` for libvirt, the name libvirt gives every QEMU it
  starts. The rest of the script (`ps` CPU/RSS, `-m`, `-smp` parsing) is
  shared. Allocated disk falls back to the current defaults for libvirt.

### Menu (`Menu.qml`)

- Header line under "Windows VM" shows `libvirt · win11` or the dockur
  ports line, by backend.
- The key hint line lists only the keys that apply: libvirt shows
  `[L] Open console / Start`, `[A] Auto-stop`, `[S] Shut down`, `[R]`,
  `[Esc]`.
- `run()` ignores `W` and `F` when the backend is libvirt.
- Backend `none` shows `backendReason` and only `[R]` and `[Esc]`.

### Documentation

`README.md` gets a short "libvirt/KVM" section (detection, `libvirt.conf`,
keys). `AGENTS.md` keyboard section notes that `W`/`F` are dockur-only.

## Alternatives rejected

- **Manifest/shell.json settings:** Omarchy passes no settings to menu
  plugins; adding them would need an Omarchy change.
- **Environment variables (`env =` in Hyprland):** needs a session restart to
  change and is invisible to anyone reading `~/.config/windows/`.
- **Domain name via the `open(payloadJson)` payload:** only works when the
  menu is summoned from a custom binding, not from the launcher.
- **RDP to the libvirt guest:** needs RDP enabled in Windows, credentials,
  and a new trust anchor for the guest IP (the docker-proxy root check does
  not apply). Deferred by the approved intent.
- **Domain picker in the menu:** more UI for a case (several Windows domains)
  that a one-line config solves. Deferred by the approved intent.
- **`virsh destroy` fallback for `S`:** risks data loss in the guest.
  Deferred by the approved intent.
- **Backend logic in QML:** would spread validation and command building
  across QML and shell; AGENTS.md keeps VM behaviour in the launcher.

## Risks

- **Dockur regression:** `stopVm()` now goes through the launcher, and
  `winvm-stats.sh` takes its pattern as an argument. Covered by the dockur
  checks in Verification.
- **libvirt access denied:** a user without `libvirtd` group membership gets
  a `virsh` error on `qemu:///system`. The launcher reports it as
  `backendReason`; it never escalates.
- **Polling cost:** `virsh domstate` every 4 s while the plugin is loaded
  (`keepLoaded: true`). It's one short local socket call, the same order as
  today's `ss` probe.
- **Detection picks the wrong domain:** only possible with exactly one
  Windows-tagged domain, which then is the user's Windows VM; anything else
  needs `DOMAIN`.
- **`virt-viewer --attach`** needs a local display (SPICE or VNC) on the
  domain. Domains with no graphics device can't be opened; the launcher
  reports the viewer's exit status.
- **Author's host:** `win11` is real user data. The host test only starts,
  views and gracefully shuts it down.

## Verification

1. `devenv shell -- validate` passes, with no new qmllint warnings.
2. Launcher self-check: a small `dev/test-launcher` script runs
   `resolve_backend` against stub `omarchy-windows-vm`, `virsh` and
   `virt-viewer` on `PATH` and checks the dockur, libvirt (configured,
   auto-detected, ambiguous, invalid `DOMAIN`, invalid `URI`) and none cases.
3. Disposable VM (`nixarchy-try`): enable `virtualisation.libvirtd`
   declaratively in the guest, define a tiny domain with the Windows
   `libosinfo` tag (no Windows install needed), then check the menu shows
   `libvirt · <domain>`, `L` starts it and opens `virt-viewer`, `S` shuts it
   down, `W`/`F` are hidden and ignored, `R`/`Esc` unchanged.
4. Host (after 3, with your OK at that point): with no `libvirt.conf`, the
   menu detects `win11`; `L` starts it and opens the console; `S` shuts it
   down gracefully; `winvm-stats.sh` reports its vCPU and memory while it
   runs.
