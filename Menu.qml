import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Windows VM controls in the Omarchy menu. Keyboard first: L/A/W/F/S/R, Esc.
// Layout follows the original bar panel: header, status banner, endpoints,
// resources, quick actions. Content adapts to the dockur or libvirt backend.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property var targetScreen: null

  readonly property color foreground: Color.menu.text
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color surfaceTint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.04)
  // ponytail: the theme has no "ok"/"busy" tokens; these status-dot colours match the original panel.
  readonly property color okColor: "#2ecc71"
  readonly property color busyColor: "#f39c12"

  readonly property bool isLibvirt: service.backend === "libvirt"
  readonly property bool isNone: service.backend === "none"

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

  // Single path for keys and buttons, so backend gating applies to both.
  function run(key) {
    var k = key.toUpperCase()
    if (root.isNone && k !== "R") return
    if (root.isLibvirt && (k === "W" || k === "F")) return
    switch (k) {
    case "L":
      if (service.vmState === "running") service.attachRdp()
      else service.launchVm("rdp-keepalive")
      close()
      break
    case "A": service.launchVm("rdp-autostop"); close(); break
    case "W": service.openWebConsole(); close(); break
    case "F": service.openSharedFolder(); close(); break
    case "S": service.stopVm(); break
    case "R": service.refreshBackend(); service.poll(); break
    }
  }

  function subtitle() {
    if (root.isNone) return "No Windows VM found"
    if (service.vmState === "running") {
      var up = service.uptimeSecs > 0 ? "  •  " + service.formatUptime(service.uptimeSecs) : ""
      var client = root.isLibvirt ? "Console open" : "RDP attached"
      return (service.rdpClientRunning ? client : "Running") + up
    }
    if (service.vmState === "starting") return root.isLibvirt ? "Starting VM…" : "Starting container…"
    if (service.vmState === "stopping") return root.isLibvirt ? "Shutting down…" : "Stopping container…"
    return "Stopped"
  }

  function badgeText() {
    if (root.isNone) return "OFF"
    if (service.vmState === "running") return "RUNNING"
    if (service.vmState === "starting") return "BOOTING"
    if (service.vmState === "stopping") return "STOPPING"
    return "STOPPED"
  }

  // One endpoint/status line: icon, label, and an Active/Offline marker.
  component StatusRow: Row {
    id: statusRow
    property string icon: ""
    property string label: ""
    property bool active: false
    property string activeText: "● Active"
    property string idleText: "○ Offline"
    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(18)
      text: statusRow.icon
      color: statusRow.active ? Color.accent : Qt.darker(Color.menu.text, 1.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: statusRow.width - Style.space(26) - stateText.implicitWidth
      text: statusRow.label
      color: Color.menu.text
      elide: Text.ElideRight
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Text {
      id: stateText
      anchors.verticalCenter: parent.verticalCenter
      text: statusRow.active ? statusRow.activeText : statusRow.idleText
      color: statusRow.active ? "#2ecc71" : Qt.darker(Color.menu.text, 1.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }

  // One resource line with an optional usage bar.
  component ResourceRow: Column {
    id: resourceRow
    property string icon: ""
    property string label: ""
    property string value: ""
    property bool highlight: false
    property bool showBar: false
    property real fraction: 0
    property real urgentAt: 0.85
    width: parent ? parent.width : 0
    spacing: Style.space(3)

    Row {
      width: parent.width
      spacing: Style.space(8)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(18)
        text: resourceRow.icon
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: resourceRow.width - Style.space(26) - valueText.implicitWidth
        text: resourceRow.label
        color: Color.menu.text
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        id: valueText
        anchors.verticalCenter: parent.verticalCenter
        text: resourceRow.value
        color: resourceRow.highlight ? Color.accent : Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }
    Rectangle {
      visible: resourceRow.showBar
      width: parent.width
      height: Style.space(3)
      radius: height / 2
      color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.1)
      Rectangle {
        width: parent.width * Math.min(1, Math.max(0, resourceRow.fraction))
        height: parent.height
        radius: parent.radius
        color: resourceRow.fraction > resourceRow.urgentAt ? Color.urgent : Color.accent
      }
    }
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
    // ponytail: extra dim; some themes ship an almost transparent menu scrim.
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45) }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      width: Math.min(Style.space(400), Math.round(panel.width * 0.9))
      height: Math.min(content.implicitHeight + card.contentTopInset + card.contentBottomInset,
                      Math.round(panel.height * 0.9))
      anchors.centerIn: parent
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18), 1)
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

        // Scrolls only when the card is capped by a short screen.
        Flickable {
          id: scroller
          anchors.fill: parent
          contentHeight: content.implicitHeight
          clip: true
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: content
            width: scroller.width
            spacing: Style.space(12)

            // 1. Header: icon, title, state subtitle, status pill
            Item {
              width: parent.width
              height: Math.max(headerText.implicitHeight, badge.implicitHeight)

              Text {
                id: headerIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "󰍲"
                color: service.vmState === "stopping" ? Color.urgent
                     : (service.isRunning || service.vmState === "starting") ? Color.accent : root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.display
              }

              Column {
                id: headerText
                anchors.left: headerIcon.right
                anchors.leftMargin: Style.space(12)
                anchors.right: badge.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: "Windows VM"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  width: parent.width
                  text: root.subtitle()
                  color: root.dim
                  elide: Text.ElideRight
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              BorderSurface {
                id: badge
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: Style.space(26)
                implicitWidth: badgeRow.implicitWidth + Style.space(16)
                color: "transparent"
                borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
                radius: Style.cornerRadius

                Row {
                  id: badgeRow
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(8)
                    height: width
                    radius: width / 2
                    color: service.isRunning ? root.okColor : service.isTransitioning ? root.busyColor : root.dim
                    SequentialAnimation on opacity {
                      running: service.isTransitioning && root.opened
                      loops: Animation.Infinite
                      NumberAnimation { from: 1.0; to: 0.2; duration: 500 }
                      NumberAnimation { from: 0.2; to: 1.0; duration: 500 }
                    }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.badgeText()
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }

            // Status banner (transition messages, timeouts, backend reason)
            BorderSurface {
              visible: bannerText.text !== ""
              width: parent.width
              implicitHeight: bannerRow.implicitHeight + Style.space(14)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              radius: Style.cornerRadius

              Row {
                id: bannerRow
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - Style.space(16))
                spacing: Style.space(8)

                Text {
                  visible: service.isTransitioning
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰔟"
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  RotationAnimation on rotation {
                    from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                    running: service.isTransitioning && root.opened
                  }
                }
                Text {
                  id: bannerText
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.isNone ? service.backendReason : service.statusMessage
                  color: root.foreground
                  wrapMode: Text.Wrap
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }

            // 2. Endpoints: dockur ports, or the libvirt domain and console
            BorderSurface {
              visible: !root.isNone
              width: parent.width
              implicitHeight: endpoints.implicitHeight + Style.space(16)
              color: root.surfaceTint
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              radius: Style.cornerRadius

              Column {
                id: endpoints
                width: parent.width - Style.space(24)
                anchors.centerIn: parent
                spacing: Style.space(8)

                StatusRow {
                  visible: !root.isLibvirt
                  icon: "󰍲"
                  label: "RDP Protocol (Port 3389)"
                  active: service.port3389Open
                }
                StatusRow {
                  visible: !root.isLibvirt
                  icon: "󰖟"
                  label: "Web Console (Port 8006)"
                  active: service.port8006Open
                }
                StatusRow {
                  visible: root.isLibvirt
                  icon: "󰍲"
                  label: "libvirt domain (" + service.domain + ")"
                  active: service.isRunning
                  activeText: "● Running"
                  idleText: service.vmState === "stopping" ? "◌ Stopping" : "○ Shut off"
                }
                StatusRow {
                  visible: root.isLibvirt
                  icon: "󰹑"
                  label: "Console (virt-viewer)"
                  active: service.rdpClientRunning
                  activeText: "● Open"
                  idleText: "○ Closed"
                }
                StatusRow {
                  visible: !root.isLibvirt && service.rdpClientRunning
                  icon: "󰹑"
                  label: "FreeRDP client"
                  active: true
                  activeText: "● Attached"
                }
              }
            }

            // 3. Resources: live usage while running, allocation otherwise
            BorderSurface {
              visible: !root.isNone
              width: parent.width
              implicitHeight: resourceColumn.implicitHeight + Style.space(16)
              color: root.surfaceTint
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              radius: Style.cornerRadius

              Column {
                id: resourceColumn
                width: parent.width - Style.space(24)
                anchors.centerIn: parent
                spacing: Style.space(8)

                Text {
                  text: service.isRunning ? "RESOURCE USAGE (LIVE)" : "RESOURCE ALLOCATION (STANDBY)"
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 0.8
                }
                ResourceRow {
                  icon: "󰻠"
                  label: service.isRunning ? "Processor (" + service.allocatedCores + " vCPU)" : "CPU Cores Allocation"
                  // ps reports % of one core; scale by the allocated vCPUs.
                  readonly property real share: service.cpuUsagePct / Math.max(1, service.allocatedCores)
                  value: service.isRunning ? share.toFixed(1) + "%" : service.allocatedCores + " Cores"
                  highlight: service.isRunning
                  showBar: service.isRunning
                  fraction: share / 100
                  urgentAt: 0.8
                }
                ResourceRow {
                  icon: "󰍛"
                  // Share of the allocated RAM; falls back to % of host RAM if allocation is unknown.
                  readonly property real allocGb: parseFloat(service.allocatedRam) || 0
                  readonly property real share: allocGb > 0 ? service.memUsageGb / allocGb : service.memUsagePct / 100
                  label: service.isRunning ? "Memory (" + service.allocatedRam + ")" : "RAM Allocation"
                  value: service.isRunning
                    ? service.memUsageGb.toFixed(1) + " GB (" + (share * 100).toFixed(0) + "%)"
                    : service.allocatedRam + " RAM"
                  highlight: service.isRunning
                  showBar: service.isRunning
                  fraction: share
                }
                ResourceRow {
                  // ponytail: disk stats come from dockur's data.img only; no libvirt source yet.
                  visible: !root.isLibvirt
                  icon: "󰋊"
                  label: service.isRunning ? "Virtual Disk (" + service.allocatedDisk + ")" : "Virtual Disk Allocation"
                  value: service.isRunning
                    ? service.hostDiskUsage + " on host"
                    : service.allocatedDisk + (service.hostDiskUsage !== "0 GB" ? " (" + service.hostDiskUsage + " host)" : "")
                }
              }
            }

            // 4. Quick actions
            Text {
              visible: !root.isNone
              text: "QUICK ACTIONS"
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.1
            }

            Column {
              visible: !root.isNone
              width: parent.width
              spacing: Style.space(6)

              Button {
                visible: service.vmState === "stopped"
                width: parent.width
                text: (root.isLibvirt ? "Start Windows VM" : "Launch Windows VM") + " [L]"
                iconText: "󰍲"
                leftAlign: true
                bordered: true
                fontFamily: Style.font.family
                fontSize: Style.font.body
                onClicked: root.run("L")
              }
              Button {
                visible: service.vmState === "running" && !service.rdpClientRunning
                         && (root.isLibvirt || service.port3389Open)
                width: parent.width
                text: root.isLibvirt ? "Open Console [L]" : "Attach FreeRDP [L]"
                iconText: root.isLibvirt ? "󰹑" : "󰍲"
                leftAlign: true
                bordered: true
                fontFamily: Style.font.family
                fontSize: Style.font.body
                onClicked: root.run("L")
              }
              Button {
                visible: !root.isLibvirt
                width: parent.width
                text: "Open Web Console [W]"
                iconText: "󰖟"
                leftAlign: true
                bordered: true
                fontFamily: Style.font.family
                fontSize: Style.font.body
                onClicked: root.run("W")
              }
              Button {
                visible: !root.isLibvirt
                width: parent.width
                text: "Open Shared Folder [F]"
                iconText: "󰉋"
                leftAlign: true
                bordered: true
                fontFamily: Style.font.family
                fontSize: Style.font.body
                onClicked: root.run("F")
              }
              Button {
                visible: service.vmState === "stopped"
                width: parent.width
                text: "Launch (Auto-Stop on Close) [A]"
                iconText: "󱐋"
                leftAlign: true
                bordered: true
                fontFamily: Style.font.family
                fontSize: Style.font.body
                onClicked: root.run("A")
              }
              Button {
                visible: service.vmState === "running" || service.vmState === "starting"
                width: parent.width
                text: (root.isLibvirt ? "Shut Down VM" : "Stop VM / Shut Down") + " [S]"
                iconText: "󰐥"
                leftAlign: true
                bordered: true
                foreground: root.dim
                fontFamily: Style.font.family
                fontSize: Style.font.body
                onClicked: root.run("S")
              }
            }
          }
        }
      }
    }
  }
}
