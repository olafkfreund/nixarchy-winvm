---
status: draft
issue: 3
spec: spec/2026-10-02-3-libvirt-backend.md
---

# Plan: Control libvirt/KVM Windows VMs from the menu

Branch `feat/3-libvirt-backend`, stacked on `feat/menu-quick-shell` (PR #2).
Line numbers are from commit `267703f`.

## Approved decisions (from spec and intent)

- Two backends: `dockur` (existing, unchanged behaviour) and `libvirt`.
  `winvm-launcher.sh` owns backend choice and every VM command; QML only asks
  it and renders.
- Resolution order: dockur if `omarchy-windows-vm status` exits 0 (exits 1
  when not configured); else libvirt if `virsh` exists and a domain is found;
  else `none`.
- Domain: `DOMAIN` from `${XDG_CONFIG_HOME:-$HOME/.config}/windows/libvirt.conf`
  (key=value, same format as `credentials`) if valid and
  `virsh -c URI dominfo DOMAIN` succeeds; else the single domain in
  `virsh -c URI list --all --name` whose `dumpxml` contains
  `libosinfo:os id="http://microsoft.com/win/`; zero or several → none.
- Validation: `DOMAIN` must match `^[A-Za-z0-9._-]{1,64}$`; `URI` must be
  `qemu:///system` (default) or `qemu:///session`. Invalid values are ignored
  and named in the reason. Values go to `virsh`/`virt-viewer` as argv only.
- libvirt actions: `L` (`rdp-keepalive`/`attach`) = `virsh start` if shut
  off, then `virt-viewer --connect URI --attach --wait DOMAIN`; `A`
  (`rdp-autostop`) = same, then `virsh shutdown` when the viewer exits; `S`
  (new `stop` mode) = `virsh shutdown` only, never `destroy`. `W` and `F` are
  hidden and ignored. No credentials and no RDP for libvirt.
- Missing `virt-viewer`: `notify-send` error naming it; do not start the
  domain.
- `backend` launcher mode prints one JSON line:
  `{"backend":"libvirt","domain":"win11","uri":"qemu:///system"}`,
  `{"backend":"dockur"}` or `{"backend":"none","reason":"…"}`.
- libvirt state: `virsh -c URI domstate DOMAIN`: `running` → running,
  `shut off` → stopped, `in shutdown` → stopping, anything else → stopped
  with the raw state in `statusMessage`. "Client attached" = a `virt-viewer`
  for the domain is running.
- Stats: `winvm-stats.sh` takes its QEMU match pattern as `$1`
  (`process=windows` for dockur, `-name guest=DOMAIN,` for libvirt). libvirt's
  emulator on the author's host is `/run/libvirt/nix-emulators/qemu-system-x86_64`,
  so the shared `qemu-system-x86_64.*` prefix matches.
- Menu: header shows `libvirt · DOMAIN` or the dockur ports line; the key hint
  lists only keys that apply; backend `none` shows the reason with `[R]` and
  `[Esc]` only.
- Docs: README "libvirt/KVM" section; AGENTS.md notes `W`/`F` are dockur-only.

**Planner addition, needs approval:** the current `Menu.qml` displays no
stats at all, yet the intent promises "basic stats". Step 5 adds one caption
line while running, for both backends: `N vCPU · X.X GB · Y% CPU`. Drop it
from step 5 if not wanted.

## Steps

1. `winvm-launcher.sh`: add the libvirt backend.
   - After `run_freerdp()` (ends line 193), add:
     - `read_libvirt_conf`: reads `DOMAIN`/`URI` with the same
       `grep -E '^KEY=' | head -n1 | cut -d= -f2- | tr -d '\r\n'` idiom as
       `run_freerdp` lines 134–139; validates both as above.
     - `resolve_backend`: sets globals `BACKEND`, `DOMAIN`, `URI`, `REASON`
       in the approved order.
     - `print_backend`: emits the JSON line. Escape `"` and `\` in `REASON`
       (or build it from fixed strings plus the validated domain only).
     - `libvirt_open <autostop>`: checks `command -v virt-viewer` (else
       `notify-send -u critical` and return 1); `virsh -c "$URI" domstate`
       → `virsh start` if `shut off`; run `virt-viewer --connect "$URI"
       --attach --wait "$DOMAIN"` (foreground, logged to `$LOG_FILE`); if
       autostop, `virsh -c "$URI" shutdown "$DOMAIN"` afterwards.
   - In the main block (line 195), before `case "$MODE"`: call
     `resolve_backend`; add a `backend)` mode that prints and exits for every
     backend; if `BACKEND=libvirt`, dispatch `attach|rdp-keepalive` →
     `libvirt_open 0`, `rdp-autostop` → `libvirt_open 1`, `stop` →
     `virsh shutdown`, anything else → exit 0; then `exit`.
   - Add a `stop)` arm to the existing dockur `case` that runs
     `omarchy-windows-vm stop` (today's QML command).
   - → verify: `bash -n winvm-launcher.sh`; step 2's test.
   Traps: `set -euo pipefail` is on, so every probe (`omarchy-windows-vm
   status`, `virsh dominfo/list/dumpxml`) needs `|| true` or an `if`. Keep
   the `BASH_SOURCE` guard so the file can be sourced by the test. Never
   `eval`, never pass values through `sh -c`. Don't touch the dockur
   fingerprint/credential code (lines 18–193).

2. `dev/test-launcher` (new, executable bash): the one runnable check for
   step 1. Creates a temp dir with stub `omarchy-windows-vm`, `virsh` and
   `virt-viewer` on `PATH`, sets `HOME`/`XDG_CONFIG_HOME`/`XDG_CACHE_HOME`
   to the temp dir, sources `winvm-launcher.sh`, and asserts `print_backend`
   output for: dockur configured; libvirt via `libvirt.conf`; libvirt
   auto-detected (one tagged domain); ambiguous (two tagged) → none; invalid
   `DOMAIN` (`a;b`) → ignored; invalid `URI` → default; no `virsh` → none.
   Add `bash dev/test-launcher` to `scripts.validate` in `devenv.nix` and
   `dev/test-launcher` to its `bash -n` line.
   → verify: `devenv shell -- validate`.
   Traps: sourcing runs the launcher's top-level `mkdir`/`touch` lines (8–15),
   which is why `HOME` and the XDG dirs must point at the temp dir first.

3. `winvm-stats.sh:43`: `pattern="${1:-process=windows}"` and
   `pid=$(pgrep -f "qemu-system-x86_64.*$pattern" | head -n1 || true)`;
   update the `ponytail:` comment on line 42.
   → verify: `bash -n`; `bash winvm-stats.sh` and
   `bash winvm-stats.sh '-name guest=win11,'` each print `"running":false`
   with the VMs off.
   Traps: run it as its own command; a shell whose command line contains the
   pattern makes `pgrep -f` match itself (seen in this session).

4. `WinVmService.qml`: backend-aware state.
   - Add `property string backend: ""`, `domain`, `uri`, `backendReason`.
   - Add a `backendProcess` (`[launcherScriptPath(), "backend"]`,
     `StdioCollector`) that parses the JSON into those properties; run it in
     `Component.onCompleted` and from `poll()` when `R` is pressed (add
     `refreshBackend()`; `Menu.qml`'s `R` calls it plus `poll()`).
   - Add a `domstateProcess`
     (`["virsh", "-c", root.uri, "domstate", root.domain]`) with a
     `handleDomstate(text)` implementing the approved mapping, including the
     `starting` → `running` hand-off that `handleProbeOutput` does today.
   - `poll()` (line 72): for libvirt run `domstateProcess` instead of
     `probeProcess`; for `none` run neither.
   - `rdpCheckProcess` (line 203): command becomes
     `["pgrep", "-f", backend === "libvirt" ? "virt-viewer .*" + domain + "$" : "xfreerdp"]`.
   - `statsProcess` (line 213): pass the pattern argument per backend.
   - `stopVm()` (line 113): `execDetached(["uwsm", "app", "--", launcherScriptPath(), "stop"])`.
   → verify: `devenv shell -- validate` (no new qmllint warnings vs 17).
   Traps: keep VM commands in the launcher; QML only builds argv from values
   the launcher already validated.

5. `Menu.qml`: backend-aware UI.
   - `run()` (line 45): ignore `W`/`F` when `service.backend === "libvirt"`;
     ignore everything except `R` when `service.backend === "none"`; `R`
     calls `service.refreshBackend()` and `service.poll()`.
   - Ports line (line 143): show `"libvirt · " + service.domain` for libvirt,
     `service.backendReason` for none, the current text for dockur.
   - Key hint (line 161): libvirt `[L] Open console` / `Start Windows VM`,
     `[A] Auto-stop`, `[S] Shut down`, `[R] Refresh`, `[Esc] Close`; none
     `[R] Refresh    [Esc] Close`; dockur unchanged.
   - (Planner addition) one caption `Text` under the ports line, visible
     while running: `service.allocatedCores + " vCPU · " +
     service.memUsageGb.toFixed(1) + " GB · " + service.cpuUsagePct.toFixed(0) + "% CPU"`.
   → verify: `devenv shell -- validate`.
   Traps: theme tokens only (`Color.menu.*`, `Style.font.*`); keep the card
   insets from `c5af9f0`; keep `L/A/W/F/S/R/Esc` stable for dockur.

6. `README.md` and `AGENTS.md`: README "libvirt/KVM" section (detection
   order, `libvirt.conf` example, keys, `virt-viewer` requirement); AGENTS.md
   keyboard section adds "`W` and `F` apply to the dockur backend only".
   → verify: commands and paths match steps 1–5.

7. Guest test (`nixarchy-try`): add `virtualisation.libvirtd.enable = true;`,
   `programs.virt-manager.enable = true;` and `demo` to `libvirtd` in the
   guest's `/etc/nixos/hosts/nixarchy-winvm/configuration.nix`, then
   `sudo nixos-rebuild switch`; define a tiny domain (64 MiB, no disk, VNC
   graphics, libosinfo `win/11` tag) with `virsh define`. Deploy the plugin
   over SSH and check: menu shows `libvirt · <domain>`; `L` starts it and
   opens `virt-viewer`; `S` shuts it down (a diskless domain may ignore ACPI;
   then confirm the `virsh shutdown` call in `$LOG_FILE`); `W`/`F` ignored;
   `R`/`Esc` unchanged. Record any guest configuration in
   `docs/vm-testing.md`.
   Traps: guest changes only through the rebuild (AGENTS.md); input via QMP
   or the guest `ai-mirror`, never host tools.

8. Host test, with the user's OK at that point: `./dev/sync` (no
   `RESTART_SHELL` unless the user agrees), menu detects `win11` with no
   `libvirt.conf`; `L` starts and opens it; stats caption shows 20 vCPU;
   `S` shuts it down gracefully.

The plan has 6 file-editing steps, so steps 1–6 go to the `coder` agent
(managed policy); step 7–8 testing and review stay with the session model,
and a fresh Opus agent reviews `git diff` against this plan.

## Tests

```sh
devenv shell -- validate          # omarchy validate, qmllint (≤17 warnings), bash -n, py_compile, dev/test-launcher
bash winvm-stats.sh               # "running":false with no VM
bash winvm-stats.sh '-name guest=win11,'
```

Then steps 7 and 8.

## Rollback

Revert the implementation commits on `feat/3-libvirt-backend`; the dockur
path returns to its `267703f` behaviour. Users can delete
`~/.config/windows/libvirt.conf`. No libvirt state is changed by the plugin
beyond start/shutdown of the chosen domain.
