---
status: draft
issue: none — GitHub Issues are disabled for this repository
author: olafkfreund
---

# Intent: Convert Windows VM controls to an Omarchy menu popout

## Problem

The plugin is currently registered as a `bar-widget`, so it adds a Windows VM
indicator and panel to the top bar. The requested interaction is instead an
Omarchy menu-only popout that can be summoned from the menu and operated from
the keyboard.

## Proposed outcome

Omarchy discovers the plugin as a `menu`, opens a focused fullscreen popout
from the Omarchy menu, and keeps the existing Windows VM actions available by
keyboard. No top-panel widget is installed or required.

## Affected users and systems

- Omarchy Quattro / long-running Quickshell plugin host.
- The Windows VM service and its launcher/stat scripts.
- Users who summon the plugin from the Omarchy menu or its menu keybinding.

## Constraints

- Follow the Omarchy plugin development contract: `menu` kind, `Menu.qml`,
  exclusive keyboard focus, focused-screen targeting, and lifecycle methods.
- Reuse the existing `WinVmService.qml` and shell scripts.
- Preserve the existing keyboard shortcuts and security checks.
- Do not start a second Quickshell process, add a top-panel widget, or add a
  new dependency.
- Validate the manifest, QML, and shell scripts before runtime testing.

## Open questions

- None. GitHub issue creation was attempted but is unavailable because Issues
  are disabled for this repository.
