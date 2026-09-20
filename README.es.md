## Configuración

La entrada del widget vive en `~/.config/omarchy/shell.json`:

```json
{
  "id": "nezbit.rackwatch",
  "url": "http://127.0.0.1:8080",
  "token": "",
  "refreshIntervalSec": 5
}
```

> Si tu instancia de RackWatch tiene autenticación activada, configura el mismo valor de `token` que usa `RACKWATCH_API_TOKEN` en el servidor. El plugin se autentica con `X-API-Key`, y un inicio de sesión del navegador por sí solo no basta para los endpoints de mutación.

También puedes cambiar valores no secretos con la CLI:

```bash
omarchy bar set nezbit.rackwatch url "http://127.0.0.1:8080"
omarchy bar set nezbit.rackwatch refreshIntervalSec 5 --json
```
