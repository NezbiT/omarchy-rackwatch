# RackWatch para Omarchy (`nezbit.rackwatch`)

Widget de la barra de Omarchy para consultar el estado de un homelab RackWatch y realizar operaciones básicas sin abrir el panel web.

> **English documentation:** See [README.md](README.md).

## Relación con RackWatch

Este plugin es el **cliente de escritorio para la barra de estado de Omarchy** y necesita una instancia activa de [RackWatch](https://github.com/NezbiT/rackwatch). El asistente incluido puede conectarla o instalarla localmente con Docker.

El plugin no interactúa directamente con el demonio de Docker ni almacena métricas por sí mismo; se comunica de forma periódica con la API REST (`/api/v1`) de tu instancia de RackWatch.

---

## Qué muestra

### En la barra de estado

- **Normal / Saludable:** Icono de servidor en rack + uso de CPU (ej. `RW · 18% CPU`).
- **Alerta / Contenedor caído:** Icono en rojo con triángulo de advertencia + contador (ej. `󰅚 1 down`).
- **Desconectado / Offline:** Icono de rack + estado (`RW · offline`).

### En el panel desplegable

- **Salud de servicios clave:** Indicadores de estado de Prometheus, Docker, Home Assistant y MQTT.
- **Métricas del host:** Barras porcentuales de CPU, RAM, disco, carga y estado de pools ZFS (`ONLINE`, `DEGRADED`).
- **Gestión de contenedores:** Lista con nombre, imagen, memoria y estado de salud (`healthy`, `running`, `exited`).
- **Reinicio protegido:** Botón `󰑓` con diálogo de confirmación para evitar reinicios por error.
- **Alertas activas:** Listado de eventos recientes con botón `Ack` para confirmarlas.
- **Retroalimentación en vivo:** Mensaje visual de éxito o detalle exacto del error.
- **Acceso web rápido:** Botón `Open Web UI ↗` para abrir el panel completo.

## Cómo funciona

```text
Panel.qml → Service.qml → collector.sh → API /api/v1 de RackWatch
```

El plugin consulta periódicamente `GET /api/v1/snapshot`. Las acciones utilizan los endpoints de reinicio de contenedores y confirmación de alertas. No accede directamente al socket de Docker.

## Instalación rápida

### Opción recomendada: asistente interactivo

Copia y pega esta única orden:

```bash
omarchy plugin add https://github.com/NezbiT/omarchy-rackwatch.git --enable && \
~/.config/omarchy/plugins/nezbit.rackwatch/setup-rackwatch
```

El asistente ofrece dos caminos:

1. **Conectar CasaOS u otro servidor existente.** Solicita la URL y el token de forma oculta, valida `/api/v1/snapshot` y solo entonces guarda la configuración.
2. **Instalar RackWatch localmente.** Comprueba Docker, clona RackWatch en `~/.local/share/rackwatch`, genera secretos aleatorios, levanta Docker Compose, espera el `healthcheck` y conecta el widget.

El token nunca se imprime ni se pasa como argumento de proceso. Si la validación falla, `shell.json` no se modifica.

### Instalación local casi automática

Para instalar el plugin y el servidor RackWatch local con una sola orden no interactiva:

```bash
omarchy plugin add https://github.com/NezbiT/omarchy-rackwatch.git --enable --yes && \
~/.config/omarchy/plugins/nezbit.rackwatch/setup-rackwatch --install-local --yes
```

Esto requiere `git`, Docker con Compose v2, `openssl`, `curl` y `jq`. No reemplaza un directorio ajeno ni una copia de RackWatch con cambios sin guardar.

### Conectar CasaOS

Si RackWatch ya está en CasaOS:

```bash
~/.config/omarchy/plugins/nezbit.rackwatch/setup-rackwatch \
  --connect http://IP-DE-CASAOS:8180
```

El asistente solicita el token sin mostrarlo. Por seguridad, un token no puede enviarse a una dirección remota por HTTP: usa HTTPS, una VPN/túnel con terminación local o deja el servidor sin token únicamente dentro de una red local confiable. El asistente no inicia sesión por SSH ni cambia contenedores remotos.

### Instalación manual

```bash
omarchy plugin add https://github.com/NezbiT/omarchy-rackwatch.git --enable
omarchy plugin validate ~/.config/omarchy/plugins/nezbit.rackwatch
```

Dependencias mínimas del widget: Omarchy 4.x, `bash`, `curl`, `jq` y `xdg-open`. Compruébalas con:

```bash
command -v bash curl jq xdg-open
```

Los cambios se recargan automáticamente. Si fuese necesario:

```bash
omarchy-shell shell rescanPlugins
```

### Actualización

Actualiza el plugin y, si usas la instalación Docker local administrada por el asistente, actualiza también RackWatch:

```bash
omarchy plugin update nezbit.rackwatch --yes && \
~/.config/omarchy/plugins/nezbit.rackwatch/setup-rackwatch --install-local --yes
```

El asistente usa `git pull --ff-only`; se detiene si detecta cambios locales y conserva `.env`, los secretos y los volúmenes Docker existentes.

### Desinstalación

Quita el widget de Omarchy con:

```bash
omarchy plugin remove nezbit.rackwatch --yes
```

Esto no detiene ni elimina el servidor RackWatch, su `.env`, base de datos o volúmenes Docker. Si instalaste el servidor local con el asistente y también quieres detenerlo sin borrar datos:

```bash
docker compose --file ~/.local/share/rackwatch/docker-compose.yml \
  --project-directory ~/.local/share/rackwatch down
```

No añadas `--volumes` salvo que quieras borrar permanentemente los datos administrados por Docker.

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

Si RackWatch tiene autenticación activada, configura el mismo token usado por `RACKWATCH_API_TOKEN` en el servidor. El plugin se autentica mediante `X-API-Key`; iniciar sesión en el navegador no autentica las mutaciones del API.

Cambia valores no secretos con la CLI:

```bash
omarchy bar set nezbit.rackwatch url "http://127.0.0.1:8080"
omarchy bar set nezbit.rackwatch refreshIntervalSec 5 --json
```

El intervalo permitido es de 2 a 60 segundos.

### Puertos habituales

- Docker Compose normal: `http://SERVIDOR:8080`
- Overlay de CasaOS: `http://SERVIDOR:8180`

Usa el puerto publicado por el servidor, no el puerto interno del contenedor.

## Token, seguridad y privacidad

- El token queda almacenado en `shell.json`; conserva ese archivo con permisos `600`.
- El plugin entrega el token al colector por entrada estándar, nunca como argumento de proceso.
- `curl` lo lee desde un archivo temporal con permisos `600`, eliminado al terminar.
- Un token solo se envía por HTTPS o a loopback (`localhost`, `127.0.0.1`, `::1`). Una URL loopback puede incluir puerto y ruta base.
- Se rechazan query strings, fragmentos, credenciales dentro de URLs, puertos inválidos y esquemas distintos de HTTP/HTTPS. Se aceptan aliases locales con `_` y FQDN absolutos terminados en `.`.
- No publiques RackWatch directamente en Internet. Prefiere HTTPS detrás de un proxy autenticado, VPN o túnel seguro.
- RackWatch puede controlar Docker. Mantén su denylist/allowlist y protege el API con token.
- El plugin no incorpora telemetría ni envía información a terceros.

Los nombres de hosts, contenedores y alertas recibidos se mantienen en memoria para dibujar el panel.

## Uso

- **Clic izquierdo:** Abrir o cerrar el panel.
- **Clic derecho o central:** Forzar actualización.
- **`R` / `r`:** Actualizar desde el teclado.
- **`Esc`:** Cerrar el panel o cancelar la confirmación.
- **`Tab`:** Cambiar entre Cancelar y Reiniciar dentro de la confirmación.
- **`Enter`:** Ejecutar la opción seleccionada.
- **Botón `󰑓`:** Solicitar reinicio del contenedor.
- **Botón `Ack`:** Confirmar una alerta.

## Solución de problemas

### El widget aparece como offline

1. Comprueba el endpoint desde el escritorio:

   ```bash
   curl -fsS http://SERVIDOR:PUERTO/healthz
   ```

2. Verifica el puerto publicado (`8080` normal, frecuentemente `8180` en CasaOS).
3. Si el API responde `401`, configura el token correcto.
4. Si un servidor remoto requiere token, configura HTTPS.
5. Revisa los mensajes recientes:

   ```bash
   journalctl --user --since today --no-pager | grep -i rackwatch
   ```

### Una acción falla

El panel muestra el error devuelto por RackWatch. Las causas comunes son token inválido, contenedor protegido, Docker inaccesible o nombre fuera de la allowlist.

## Validación para desarrollo

```bash
omarchy plugin validate ~/.config/omarchy/plugins/nezbit.rackwatch
bash -n collector.sh setup-rackwatch tests/test-collector.sh tests/test-setup.sh
./tests/test-collector.sh
./tests/test-setup.sh
node tests/test-model.js
```

GitHub Actions ejecuta estas validaciones en pushes y pull requests.

## Privacidad

Los archivos distribuidos no contienen correos, nombres reales, tokens ni rutas personales. La única identidad pública dentro de los archivos es `NezbiT`.

## Licencia

MIT © NezbiT. Consulta [LICENSE](LICENSE).
