import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  readonly property string collectorScript: decodeURIComponent(String(Qt.resolvedUrl("collector.sh")).replace(/^file:\/\//, ""))

  property string url: stringSetting("url", "http://127.0.0.1:8080")
  property string token: stringSetting("token", "")
  property int refreshIntervalSec: intSetting("refreshIntervalSec", 5, 2, 60)

  property var snapshot: null
  property bool connected: false
  property bool refreshing: false
  property string lastError: ""
  property date lastUpdated: new Date(0)
  property string lastActionMessage: ""
  property bool lastActionSuccess: false

  signal actionCompleted(string action, string target, bool success)

  function setting(name, fallback) {
    var val = settings ? settings[name] : undefined
    return (val === undefined || val === null) ? fallback : val
  }

  function stringSetting(name, fallback) {
    var s = String(setting(name, fallback) || "").trim()
    return s ? s : fallback
  }

  function intSetting(name, fallback, minVal, maxVal) {
    var v = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(v)) v = fallback
    return Math.max(minVal, Math.min(maxVal, v))
  }

  function refresh() {
    if (refreshing || collector.running) return
    refreshing = true
    lastError = ""
    collector.command = ["bash", root.collectorScript, "snapshot", root.url]
    collector.running = true
  }

  function restartContainer(containerName) {
    runMutation("restart-container", containerName)
  }

  function startContainer(containerName) {
    runMutation("start-container", containerName)
  }

  function stopContainer(containerName) {
    runMutation("stop-container", containerName)
  }

  function ackAlert(alertId) {
    runMutation("ack-alert", String(alertId))
  }

  function openDashboard() {
    if (mutator.running) return
    mutator.pendingAction = "open-url"
    mutator.pendingTarget = ""
    mutator.pendingToken = ""
    mutator.command = ["bash", root.collectorScript, "open-url", root.url]
    mutator.running = true
  }

  function runMutation(actionName, target) {
    if (mutator.running) return
    mutator.pendingAction = actionName
    mutator.pendingTarget = target
    mutator.pendingToken = root.token
    mutator.command = ["bash", root.collectorScript, actionName, root.url, target]
    mutator.running = true
  }

  Timer {
    id: timer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: collector
    property string pendingToken: ""
    stdinEnabled: true
    command: []
    stdout: StdioCollector {
      id: collectorOutput
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: collectorStderr
      waitForEnd: true
    }
    onStarted: {
      pendingToken = root.token
      write(pendingToken + "\n")
      pendingToken = ""
    }
    onExited: function(exitCode) {
      root.refreshing = false
      var raw = collectorOutput.text || ""
      var parsed = Model.parseCollector(raw)
      if (!parsed.ok) {
        root.connected = false
        root.lastError = parsed.error || "Unreachable"
        return
      }
      root.connected = true
      root.lastError = ""
      root.snapshot = parsed.data
      root.lastUpdated = new Date()
    }
  }

  Process {
    id: mutator
    property string pendingAction: ""
    property string pendingTarget: ""
    property string pendingToken: ""
    stdinEnabled: true
    command: []
    stdout: StdioCollector { id: mutatorOutput; waitForEnd: true }
    stderr: StdioCollector { id: mutatorStderr; waitForEnd: true }
    onStarted: {
      write(pendingToken + "\n")
      pendingToken = ""
    }
    onExited: function(exitCode) {
      var act = mutator.pendingAction
      var tgt = mutator.pendingTarget
      var success = exitCode === 0
      var detail = ""
      try {
        var result = JSON.parse((mutatorOutput.text || "").trim())
        success = success && result.ok === true
        detail = result.detail || result.error || ""
      } catch (e) {
        success = false
        detail = (mutatorStderr.text || "").trim() || "Invalid collector response"
      }
      root.lastActionSuccess = success
      root.lastActionMessage = success ? (
        act === "ack-alert" ? "Alert acknowledged"
          : (act === "open-url" ? "Dashboard opened" : "Container " + tgt + " updated")
      ) : (detail || "Action failed")
      actionMessageTimer.restart()
      root.actionCompleted(act, tgt, success)
      if (success && act !== "open-url") root.refresh()
    }
  }

  Timer {
    id: actionMessageTimer
    interval: 6000
    repeat: false
    onTriggered: root.lastActionMessage = ""
  }
}
