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

> If your RackWatch instance has authentication enabled, configure the same `token` value used by `RACKWATCH_API_TOKEN` in the server. The plugin authenticates with `X-API-Key`, and a browser login alone is not enough for API mutation endpoints.

You can update settings via the command line:

```bash
# Set RackWatch instance URL
omarchy bar set nezbit.rackwatch url "http://127.0.0.1:8080"

# Set polling interval (2 to 60 seconds)
omarchy bar set nezbit.rackwatch refreshIntervalSec 5 --json
```
