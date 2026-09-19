.pragma library

function parseCollector(raw) {
  if (!raw || typeof raw !== "string") {
    return { ok: false, error: "Empty collector output" }
  }
  try {
    var parsed = JSON.parse(raw.trim())
    if (!parsed) return { ok: false, error: "Null JSON" }
    if (parsed.ok === false) {
      var message = parsed.error || "Unreachable"
      if (parsed.detail) message += ": " + parsed.detail
      return { ok: false, error: message }
    }
    var snap = parsed.data || {}
    return {
      ok: true,
      data: {
        instance: snap.instance || "Homelab",
        ts: snap.ts || (Date.now() / 1000),
        prometheusOk: !!snap.prometheus_ok,
        dockerOk: !!snap.docker_ok,
        haOk: !!snap.ha_ok,
        mqttOk: !!snap.mqtt_ok,
        summary: snap.summary || {},
        hosts: snap.hosts || [],
        containers: snap.containers || [],
        zfs: snap.zfs || [],
        alerts: snap.alerts || [],
        glances: snap.glances || {}
      }
    }
  } catch (e) {
    return { ok: false, error: "Invalid JSON: " + e.message }
  }
}

function formatPercent(value) {
  if (value === null || value === undefined || isNaN(value)) return "0%"
  return Math.round(Number(value)) + "%"
}

function formatBytes(bytes) {
  var b = Number(bytes)
  if (isNaN(b) || b <= 0) return "0 B"
  var gib = b / (1024 * 1024 * 1024)
  if (gib >= 1.0) return gib.toFixed(1) + " GB"
  var mib = b / (1024 * 1024)
  return mib.toFixed(0) + " MB"
}

function formatUptime(seconds) {
  var s = Number(seconds)
  if (isNaN(s) || s <= 0) return "—"
  var days = Math.floor(s / 86400)
  var hours = Math.floor((s % 86400) / 3600)
  var mins = Math.floor((s % 3600) / 60)
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + mins + "m"
  return mins + "m"
}

function timeAgo(dateOrTs) {
  if (!dateOrTs) return "just now"
  var ms
  if (typeof dateOrTs === "number") {
    ms = dateOrTs > 10000000000 ? dateOrTs : dateOrTs * 1000
  } else {
    ms = new Date(dateOrTs).getTime()
  }
  var diff = Math.max(0, (Date.now() - ms) / 1000)
  if (diff < 60) return Math.floor(diff) + "s ago"
  if (diff < 3600) return Math.floor(diff / 60) + "m ago"
  if (diff < 86400) return Math.floor(diff / 3600) + "h ago"
  return Math.floor(diff / 86400) + "d ago"
}

function overallStatus(data) {
  if (!data) return "unknown"
  var sum = data.summary || {}
  if (sum.overall) return sum.overall
  if (sum.containers_down > 0 || sum.zfs_bad > 0) return "error"
  if (sum.containers_warn > 0) return "warning"
  return "ok"
}

function containerStateBadge(c) {
  var st = (c && c.status ? String(c.status) : "").toLowerCase()
  var hl = (c && c.health ? String(c.health) : "").toLowerCase()
  if (st === "running" && hl === "unhealthy") return { label: "unhealthy", color: "warning" }
  if (st === "running") return { label: "running", color: "ok" }
  if (st === "restarting") return { label: "restarting", color: "warning" }
  if (st === "exited") return { label: "exited", color: "error" }
  if (st === "paused") return { label: "paused", color: "warning" }
  return { label: st || "unknown", color: "unknown" }
}
