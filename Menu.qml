import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Windows VM controls in the Omarchy menu. Keyboard first: L/A/W/F/S/R, Esc.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property var targetScreen: null

  readonly property color foreground: Color.menu.text
  readonly property color dim: Qt.darker(foreground, 1.45)

  WinVmService {
    id: service
    pollInterval: 4
    sharedFolderPath: "~/Windows"
  }

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === name) return screens[i]
    return null
  }

  function open(payloadJson) {
    targetScreen = focusedScreen()
    service.poll()
    opened = true
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }

  function close() { opened = false }
  function toggle() { if (opened) close(); else open("{}") }

  function run(key) {
    switch (key.toUpperCase()) {
    case "L":
      if (service.vmState === "running") service.attachRdp()
      else service.launchVm("rdp-keepalive")
      close()
      break
    case "A": service.launchVm("rdp-autostop"); close(); break
    case "W": service.openWebConsole(); close(); break
    case "F": service.openSharedFolder(); close(); break
    case "S": service.stopVm(); break
    case "R": service.poll(); break
    }
  }

  function stateText() {
    if (service.vmState === "running")
      return service.rdpClientRunning ? "Running · RDP attached" : "Running"
    if (service.vmState === "starting") return "Starting Windows VM…"
    if (service.vmState === "stopping") return "Stopping Windows VM…"
    return "Stopped"
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "nixarchy-winvm-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    onVisibleChanged: if (visible) Qt.callLater(function() { keyScope.forceActiveFocus() })

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      width: Math.min(Style.space(560), Math.round(panel.width * 0.86))
      height: Math.min(content.implicitHeight + card.contentTopInset + card.contentBottomInset,
                      Math.round(panel.height * 0.82))
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.max(Style.gapsOut, Math.round((panel.height - height) / 3))
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      FocusScope {
        id: keyScope
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        focus: true

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
            return
          }
          if (event.modifiers === Qt.NoModifier) {
            var text = event.text.toUpperCase()
            if (["L", "A", "W", "F", "S", "R"].indexOf(text) !== -1) {
              root.run(text)
              event.accepted = true
            }
          }
        }

        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          Text {
            text: "Windows VM"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            text: root.stateText()
            color: service.isTransitioning ? Color.accent : root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Text {
            text: "RDP 3389: " + (service.port3389Open ? "active" : "offline")
                + "   Web 8006: " + (service.port8006Open ? "active" : "offline")
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: service.statusMessage !== ""
            text: service.statusMessage
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            width: parent.width
          }

          Text {
            text: "[L] " + (service.vmState === "running" ? "Attach FreeRDP" : "Launch Windows VM")
                + "    [A] Auto-stop    [W] Web console\n"
                + "[F] Shared folder    [S] Stop VM    [R] Refresh    [Esc] Close"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            lineHeight: 1.35
            wrapMode: Text.Wrap
            width: parent.width
          }
        }
      }
    }
  }
}
