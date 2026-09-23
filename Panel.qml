import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "nezbit.rackwatch"
  ipcTarget: "nezbit.rackwatch"

  property double nowMs: Date.now()
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.35)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property color colorOk: "#44bb77"
  readonly property color colorWarn: "#e5c07b"
  readonly property color colorCrit: urgent

  readonly property bool connected: service.connected
  readonly property var snapshot: service.snapshot
  readonly property var summary: (snapshot && snapshot.summary && typeof snapshot.summary === "object") ? snapshot.summary : ({})
  readonly property var hosts: (snapshot && Array.isArray(snapshot.hosts)) ? snapshot.hosts : []
  readonly property var firstHost: root.hosts.length > 0 ? root.hosts[0] : null
  readonly property var containers: (snapshot && Array.isArray(snapshot.containers)) ? snapshot.containers : []
  readonly property var alerts: (snapshot && Array.isArray(snapshot.alerts)) ? snapshot.alerts : []
  readonly property var zfs: (snapshot && Array.isArray(snapshot.zfs)) ? snapshot.zfs : []
  property string pendingRestartName: ""

  readonly property string overallStatus: connected ? Model.overallStatus(snapshot) : "unknown"
  readonly property bool isError: overallStatus === "error"
  readonly property bool isWarn: overallStatus === "warning"
  readonly property int downCount: root.summary.containers_down || 0

  readonly property string barText: {
    if (!root.connected) return "RW · offline"
    if (root.downCount > 0) return "󰅚 " + root.downCount + " down"
    if (root.summary.cpu !== undefined && root.summary.cpu !== null) return "RW · " + Model.formatPercent(root.summary.cpu) + " CPU"
    return "RackWatch"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    nowMs = Date.now()
    service.refresh()
  }

  function requestRestart(containerName) {
    pendingRestartName = String(containerName || "")
    restartConfirm.selectedIndex = 0
    restartConfirm.opened = pendingRestartName.length > 0
  }

  function cancelRestart() {
    restartConfirm.opened = false
    pendingRestartName = ""
  }

  function confirmRestart() {
    var target = pendingRestartName
    restartConfirm.opened = false
    pendingRestartName = ""
    if (target) service.restartContainer(target)
  }

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    if (!service.lastUpdated || (Date.now() - service.lastUpdated.getTime()) > service.refreshIntervalSec * 1000) {
      root.refresh()
    }
    Qt.callLater(function() { catcher.forceActiveFocus() })
  }

  Service {
    id: service
    settings: root.settings
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    fixedWidth: vertical ? -1 : content.implicitWidth + Style.space(16)
    tooltipText: "RackWatch: " + (root.connected ? ((root.snapshot ? root.snapshot.instance : "Homelab") + " (" + (root.summary.containers_total || 0) + " containers)") : "offline") + "\nLeft-click: panel · Right-click: refresh"
    active: root.isError || root.isWarn

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.toggle()
      }
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(6)

      Image {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(16)
        height: Style.space(16)
        source: root.isError ? "assets/rackwatch-alert.svg" : "assets/rackwatch.svg"
        sourceSize.width: Style.space(16)
        sourceSize.height: Style.space(16)
      }

      Text {
        textFormat: Text.PlainText
        visible: !(bar ? bar.vertical : false)
        anchors.verticalCenter: parent.verticalCenter
        text: root.barText
        color: root.isError ? root.urgent : (root.isWarn ? root.colorWarn : root.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      onCloseRequested: {
        if (restartConfirm.opened) root.cancelRestart()
        else root.close()
      }
      onMoveRequested: function(dx, dy) {
        if (restartConfirm.opened && dx !== 0) restartConfirm.selectedIndex = restartConfirm.selectedIndex === 0 ? 1 : 0
      }
      onReturnRequested: {
        if (restartConfirm.opened) {
          if (restartConfirm.selectedIndex === 0) root.cancelRestart()
          else root.confirmRestart()
        }
      }
      onTextKey: function(text) {
        if (!restartConfirm.opened && (text === "r" || text === "R")) root.refresh()
      }
      onTabRequested: function(direction) {
        if (restartConfirm.opened) restartConfirm.selectedIndex = restartConfirm.selectedIndex === 0 ? 1 : 0
        else root.switchPanel(direction)
      }

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: body.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: body
          width: scroll.availableWidth
          spacing: Style.space(12)

          // Subtitle timestamp & Open Web UI button
          RowLayout {
            width: parent.width

            Text {
              textFormat: Text.PlainText
              text: "Updated " + (service.lastUpdated.getTime() > 0 ? Qt.formatTime(service.lastUpdated, "HH:mm:ss") : "never") + " · " + (service.refreshing ? "Refreshing…" : "R to refresh")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Item { Layout.fillWidth: true }

            Rectangle {
              height: Style.space(22)
              width: linkText.implicitWidth + Style.space(16)
              radius: Style.cornerRadius
              color: linkMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

              Text {
                textFormat: Text.PlainText
                id: linkText
                anchors.centerIn: parent
                text: "Open Web UI ↗"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                id: linkMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: service.openDashboard()
              }
            }
          }

          // Hero Header
          PanelHero {
            width: parent.width
            title: "RackWatch · " + (root.connected ? (root.snapshot ? root.snapshot.instance : "Homelab") : "Homelab")
            meta: root.connected ? ((root.summary.containers_total || 0) + " containers · " + (root.summary.hosts || 1) + " host" + ((root.summary.hosts || 1) > 1 ? "s" : "")) : "Server unreachable"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // Service Status Badges
          Row {
            width: parent.width
            spacing: Style.space(6)

            StatusBadge {
              label: "Prometheus"
              isOk: root.connected && root.snapshot && root.snapshot.prometheusOk
            }
            StatusBadge {
              label: "Docker"
              isOk: root.connected && root.snapshot && root.snapshot.dockerOk
            }
            StatusBadge {
              label: "HA"
              isOk: root.connected && root.snapshot && root.snapshot.haOk
            }
            StatusBadge {
              label: "MQTT"
              isOk: root.connected && root.snapshot && root.snapshot.mqttOk
            }
          }

          Rectangle {
            visible: service.lastActionMessage.length > 0
            width: parent.width
            implicitHeight: actionMessage.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: service.lastActionSuccess
              ? Qt.rgba(0.2, 0.8, 0.2, 0.12)
              : Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.12)
            border.color: service.lastActionSuccess ? root.colorOk : root.urgent
            border.width: 1

            Text {
              textFormat: Text.PlainText
              id: actionMessage
              anchors.fill: parent
              anchors.margins: Style.space(8)
              text: service.lastActionMessage
              color: service.lastActionSuccess ? root.colorOk : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          // Offline Warning Card
          Rectangle {
            visible: !root.connected
            width: parent.width
            implicitHeight: offlineCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.1)
            border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.3)
            border.width: 1

            Column {
              id: offlineCol
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(4)

              Text {
                textFormat: Text.PlainText
                text: "Cannot connect to RackWatch"
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: "URL: " + service.url + "\nError: " + (service.lastError || "Connection refused") + "\nCheck if RackWatch server is running or configure URL in settings."
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          // HOST METRICS
          Column {
            visible: root.connected
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { width: parent.width; foreground: root.foreground }

            PanelSectionHeader {
              text: "HOST METRICS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              MetricCard {
                Layout.fillWidth: true
                title: "CPU"
                percent: root.summary.cpu || 0
                detail: (root.firstHost && root.firstHost.load1 !== null && root.firstHost.load1 !== undefined) ? ("Load " + Number(root.firstHost.load1).toFixed(2)) : "—"
              }

              MetricCard {
                Layout.fillWidth: true
                title: "RAM"
                percent: root.summary.ram || 0
                detail: (root.firstHost && root.firstHost.ram_used_bytes) ? Model.formatBytes(root.firstHost.ram_used_bytes) : "—"
              }

              MetricCard {
                Layout.fillWidth: true
                title: "DISK"
                percent: root.summary.disk || 0
                detail: (root.firstHost && root.firstHost.disk_used_bytes) ? Model.formatBytes(root.firstHost.disk_used_bytes) : "—"
              }
            }

            // ZFS Pools if any
            Repeater {
              model: root.zfs

              delegate: Rectangle {
                required property var modelData
                width: parent.width
                implicitHeight: Style.space(32)
                radius: Style.cornerRadius
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)

                  Text {
                    textFormat: Text.PlainText
                    text: "ZFS: " + modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  Item { Layout.fillWidth: true }

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.health
                    color: modelData.health === "ONLINE" ? root.colorOk : root.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: Model.formatPercent(modelData.capacity_percent) + " full"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // CONTAINERS LIST
          Column {
            visible: root.connected && root.containers.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { width: parent.width; foreground: root.foreground }

            PanelSectionHeader {
              text: "CONTAINERS (" + root.containers.length + ")"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.containers

              delegate: ContainerRow {
                width: parent.width
                container: modelData
              }
            }
          }

          // ACTIVE ALERTS
          Column {
            visible: root.connected && root.alerts.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { width: parent.width; foreground: root.foreground }

            PanelSectionHeader {
              text: "ACTIVE ALERTS (" + root.alerts.length + ")"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.alerts

              delegate: AlertRow {
                width: parent.width
                alertItem: modelData
              }
            }
          }
        }
      }

      ConfirmDialog {
        id: restartConfirm
        anchors.fill: parent
        z: 20
        message: "Restart container “" + root.pendingRestartName + "”?\n\nThe service may be temporarily unavailable."
        confirmText: "Restart"
        background: Color.background
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.cancelRestart()
        onConfirmed: root.confirmRestart()
      }
    }
  }

  // --- Reusable Subcomponents ---

  component StatusBadge: Rectangle {
    property string label: ""
    property bool isOk: false
    implicitWidth: badgeRow.implicitWidth + Style.space(12)
    implicitHeight: Style.space(20)
    radius: Style.cornerRadius
    color: isOk ? Qt.rgba(0.2, 0.8, 0.2, 0.12) : Qt.rgba(0.8, 0.2, 0.2, 0.12)
    border.color: isOk ? Qt.rgba(0.2, 0.8, 0.2, 0.3) : Qt.rgba(0.8, 0.2, 0.2, 0.3)
    border.width: 1

    Row {
      id: badgeRow
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        textFormat: Text.PlainText
        text: isOk ? "●" : "○"
        color: isOk ? root.colorOk : root.urgent
        font.pixelSize: Style.font.caption
      }

      Text {
        textFormat: Text.PlainText
        text: label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component MetricCard: Rectangle {
    property string title: ""
    property real percent: 0
    property string detail: ""

    implicitHeight: Style.space(68)
    radius: Style.cornerRadius
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    border.width: 1

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(8)
      spacing: Style.space(4)

      RowLayout {
        width: parent.width
        Text {
          textFormat: Text.PlainText
          text: title
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Item { Layout.fillWidth: true }
        Text {
          textFormat: Text.PlainText
          text: Model.formatPercent(percent)
          color: percent >= 90 ? root.urgent : (percent >= 80 ? root.colorWarn : root.foreground)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      // Progress bar
      Rectangle {
        width: parent.width
        height: Style.space(6)
        radius: Style.space(3)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

        Rectangle {
          width: Math.min(parent.width, parent.width * Math.max(0, percent) / 100)
          height: parent.height
          radius: parent.radius
          color: percent >= 90 ? root.urgent : (percent >= 80 ? root.colorWarn : root.colorOk)
        }
      }

      Text {
        textFormat: Text.PlainText
        text: detail
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component ContainerRow: Rectangle {
    id: cRow
    property var container: null
    readonly property var badge: Model.containerStateBadge(container)
    implicitHeight: Style.space(44)
    radius: Style.cornerRadius
    color: cMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

    MouseArea {
      id: cMouse
      anchors.fill: parent
      hoverEnabled: true
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      // Status indicator circle
      Rectangle {
        width: Style.space(8)
        height: Style.space(8)
        radius: Style.space(4)
        color: badge.color === "ok" ? root.colorOk : (badge.color === "warning" ? root.colorWarn : root.urgent)
      }

      // Name & Image
      Column {
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          text: container ? container.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          text: (container ? container.image : "") + (container && container.memory_bytes ? (" · " + Model.formatBytes(container.memory_bytes)) : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // Restart Action Button
      Rectangle {
        width: Style.space(28)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: restartMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: "󰑓"
          color: restartMouse.containsMouse ? root.colorOk : root.foreground
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          id: restartMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (container) root.requestRestart(container.name)
        }
      }
    }
  }

  component AlertRow: Rectangle {
    property var alertItem: null
    implicitHeight: alertCol.implicitHeight + Style.space(12)
    radius: Style.cornerRadius
    color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.08)
    border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.2)
    border.width: 1

    RowLayout {
      anchors.fill: parent
      anchors.margins: Style.space(8)
      spacing: Style.space(8)

      Column {
        id: alertCol
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          text: alertItem ? alertItem.title : ""
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          text: (alertItem ? alertItem.message : "") + " · " + Model.timeAgo(alertItem ? alertItem.created_at : null)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      // Ack button
      Rectangle {
        width: ackText.implicitWidth + Style.space(12)
        height: Style.space(24)
        radius: Style.cornerRadius
        color: ackMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

        Text {
          textFormat: Text.PlainText
          id: ackText
          anchors.centerIn: parent
          text: "Ack"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        MouseArea {
          id: ackMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (alertItem && alertItem.id) service.ackAlert(alertItem.id)
        }
      }
    }
  }
}
