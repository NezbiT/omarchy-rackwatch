# RackWatch for Omarchy (`nezbit.rackwatch`)

Status bar widget and dropdown control panel for **Omarchy**, designed to monitor and manage a [RackWatch](https://github.com/NezbiT/rackwatch) homelab instance without opening the browser.

> Spanish documentation is available at [README.es.md](README.es.md).

---

## Relationship with RackWatch

> ⚠️ **Prerequisite:** This plugin is the desktop client for **[RackWatch](https://github.com/NezbiT/rackwatch)**. It **strictly requires an active, reachable RackWatch installation** running on your local machine or your home server.

The plugin does not connect directly to the Docker socket or store metrics in its own database. Instead, it interfaces with the RackWatch REST API (`/api/v1`):

```text
Panel.qml ──► Service.qml ──► collector.sh ──► RackWatch REST API (/api/v1/snapshot)
```

If you do not have RackWatch installed yet, set up the Docker Compose stack first:
[https://github.com/NezbiT/rackwatch](https://github.com/NezbiT/rackwatch).

---

## Features

### Status Bar Widget

- **Healthy / Normal:** Rack server icon + live host CPU usage (e.g., `RW · 18% CPU`).
- **Alert / Container Down:** High-contrast red warning icon with badge counter (e.g., `󰅚 1 down`).
- **Offline / Unreachable:** Distinguishable disconnected state (e.g., `RW · offline`).

### Dropdown Operations Panel

- **Service Health Badges:** Real-time connectivity indicators for Prometheus, Docker, Home Assistant, and MQTT.
- **Host Performance Gauges:** Visual percentage bars for CPU, RAM, Disk, System Load, and ZFS pool health (`ONLINE`, `DEGRADED`).
- **Container Management:** Lists container names, images, memory usage, and health states (`healthy`, `running`, `exited`).
- **Protected Restarts:** Dedicated restart button (`󰑓`) backed by a modal confirmation dialog to prevent accidental service disruptions.
- **Active Alerts:** Chronological list of unresolved alerts with an inline `Ack` button to acknowledge and silence them.
- **Execution Feedback:** Live confirmation banner showing success or exact API error details.
- **Quick Web Launch:** `Open Web UI ↗` button to open the full RackWatch dashboard in your default browser.

---

## Requirements

1. **Active RackWatch Instance:** Running via Docker Compose or CasaOS.
2. **Omarchy Desktop:** Omarchy 4.x with Omarchy Shell / Quickshell.
3. **Core CLI Tools:** `bash`, `curl`, `jq`, and `xdg-open` (`xdg-utils`).

Check installed dependencies on your system:

```bash
command -v bash curl jq xdg-open
```

---

## Installation

### Method 1: Using Omarchy Plugin Manager

```bash
omarchy plugin add https://github.com/NezbiT/omarchy-rackwatch.git --enable
```

### Method 2: Manual Installation

Clone or place the plugin directory into your Omarchy plugins path:

```bash
git clone https://github.com/NezbiT/omarchy-rackwatch.git ~/.config/omarchy/plugins/nezbit.rackwatch
```

Validate and enable the widget in the status bar:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/nezbit.rackwatch
omarchy plugin enable nezbit.rackwatch right
```

Reload plugins if needed:

```bash
omarchy-shell shell rescanPlugins
```

---

## Configuration

Configuration is stored in `~/.config/omarchy/shell.json`:

```json
{
  "id": "nezbit.rackwatch",
  "url": "http://127.0.0.1:8080",
  "token": "",
  "refreshIntervalSec": 5
}
```

If RackWatch authentication is enabled, configure the same token used by `RACKWATCH_API_TOKEN` on the server. The plugin authenticates with `X-API-Key`; a browser login does not authenticate API mutations.

You can update non-secret settings via the command line:

```bash
# Set RackWatch instance URL
omarchy bar set nezbit.rackwatch url "http://127.0.0.1:8080"

# Set polling interval (2 to 60 seconds)
omarchy bar set nezbit.rackwatch refreshIntervalSec 5 --json
```

### Common Service Ports

- **Standard Docker Compose:** `http://<SERVER_IP>:8080`
- **CasaOS Overlay:** `http://<SERVER_IP>:8180`

---

## Security & Privacy

- **Safe Credential Handling:** API tokens configured in `shell.json` are passed to `collector.sh` via standard input (`stdin`), preventing credentials from appearing in process listings (`ps`).
- **Restricted Temp Files:** Dynamic curl header files are written with `600` permissions and automatically deleted on exit.
- **Transport Security:** Tokens are rejected over unencrypted HTTP unless connecting to loopback (`localhost`, `127.0.0.1`, `::1`). Loopback URLs may include a port and base path.
- **Strict Base URLs:** Query strings, fragments, credentials in URLs, and unsupported schemes are rejected.
- **No Third-Party Telemetry:** The plugin communicates solely with your configured RackWatch endpoint.

For remote servers that require a token, use HTTPS. Do not publish a Docker-controlling RackWatch API directly to the Internet.

---

## Keyboard & Mouse Shortcuts

- **Left Click:** Open or close the dropdown panel.
- **Right / Middle Click:** Force immediate metric refresh.
- **`R` / `r`:** Refresh metrics from keyboard while the panel is focused.
- **`Esc`:** Close the panel or cancel an open confirmation dialog.
- **`Tab`:** Switch focus between *Cancel* and *Restart* buttons in confirmation dialogs.
- **`Enter`:** Execute the selected action in confirmation dialogs.
- **`󰑓` Button:** Request container restart (opens safety dialog).
- **`Ack` Button:** Acknowledge alert in RackWatch.

---

## Troubleshooting

### Widget Displays "Offline"

1. Verify that RackWatch is responding on the configured endpoint:

   ```bash
   curl -fsS http://127.0.0.1:8080/healthz
   ```

2. Confirm the published port (`8080` default, `8180` on CasaOS).
3. If the server requires authentication and returns `401 Unauthorized`, configure `token` in `shell.json`.
4. Use HTTPS if a remote server requires a token.
5. Inspect recent desktop logs:

   ```bash
   journalctl --user --since today --no-pager | grep -i rackwatch
   ```

### Action Fails with Error

The panel displays the error returned by RackWatch. Common causes include:

- Container is on the protected denylist.
- API token is missing or invalid.
- Container name is not recognized or not in the allowlist.
- Docker is unavailable on the RackWatch server.

---

## Development & Testing

```bash
omarchy plugin validate ~/.config/omarchy/plugins/nezbit.rackwatch
bash -n collector.sh tests/test-collector.sh
./tests/test-collector.sh
node tests/test-model.js
```

GitHub Actions performs the same validation on pushes and pull requests.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
