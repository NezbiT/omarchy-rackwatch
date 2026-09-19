# RackWatch para Omarchy (`nezbit.rackwatch`)

Widget de la barra de Omarchy para consultar el estado de un homelab RackWatch y realizar operaciones básicas sin abrir el panel web.

> **English documentation:** See [README.md](README.md).

## Relación con RackWatch

Este plugin es el **cliente de escritorio para la barra de estado de Omarchy** y **requiere tener instalado y en ejecución [RackWatch](https://github.com/NezbiT/rackwatch)** en tu servidor local o remoto.

El plugin no interactúa directamente con el demonio de Docker ni almacena métricas por sí mismo; se comunica de forma periódica con la API REST (`/api/v1`) de tu instancia de RackWatch.

---

## Qué muestra

### En la barra de estado
- **Normal / Saludable:** Icono de servidor en rack + uso de CPU (ej. `RW · 18% CPU`).
- **Alerta / Contenedor caído:** Icono en rojo con triángulo de advertencia + contador (ej. `󰅚 1 down`).
- **Desconectado / Offline:** Icono de rack + estado (`RW · offline`).

### En el panel desplegable
- **Salud de servicios clave:** Indicadores de estado de Prometheus, Docker, Home Assistant y MQTT.
- **Métricas del host:** Barras porcentuales de CPU, RAM, disco, load average y estado de pools ZFS (`ONLINE`, `DEGRADED`).
- **Gestión de contenedores:** Lista con nombre, imagen, memoria y estado de salud (`healthy`, `running`, `exited`).
- **Reinicio protegido:** Botón `󰑓` con diálogo de confirmación para evitar reinicios por error.
- **Alertas activas:** Listado de eventos recientes con botón `Ack` para confirmarlas.
- **Retroalimentación en vivo:** Mensaje visual en el panel (verde para éxito, rojo con detalle del error si falla).
- **Acceso web rápido:** Botón `Open Web UI ↗` para abrir el panel completo en el navegador predeterminado.

## Cómo funciona

```text
Panel.qml → Service.qml → collector.sh → API /api/v1 de RackWatch
```

El plugin consulta periódicamente `GET /api/v1/snapshot`. Las acciones utilizan los endpoints de reinicio de contenedores y confirmación de alertas. No accede directamente al socket de Docker.

## Requisitos

1. **Servidor RackWatch en ejecución:** Necesitas una instancia de [RackWatch](https://github.com/NezbiT/rackwatch) activa y accesible.
2. **Entorno de escritorio:** Omarchy 4.x con Omarchy Shell/Quickshell.
3. **Herramientas del sistema:** `bash`, `curl`, `jq` y `xdg-open` (`xdg-utils`).

En Omarchy/Arch puedes comprobar las dependencias con:

```bash
command -v bash curl jq xdg-open
```

## Instalación y activación

El directorio debe quedar en:

```text
~/.config/omarchy/plugins/nezbit.rackwatch/
```

Valida y activa el widget:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/nezbit.rackwatch
omarchy plugin enable nezbit.rackwatch right
```

Los cambios dentro del directorio se recargan automáticamente. Si fuese necesario, fuerza un nuevo escaneo:

```bash
omarchy-shell shell rescanPlugins
```

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

También puedes cambiar valores no secretos con la CLI:

```bash
omarchy bar set nezbit.rackwatch url "http://127.0.0.1:8080"
omarchy bar set nezbit.rackwatch refreshIntervalSec 5 --json
```

El intervalo permitido es de 2 a 60 segundos.

### Puertos habituales

- Docker Compose normal: `http://SERVIDOR:8080`
- Overlay de CasaOS incluido en RackWatch: `http://SERVIDOR:8180`

Usa el puerto realmente publicado por el servidor, no el puerto interno del contenedor.

## Token y seguridad

- Si RackWatch tiene `RACKWATCH_API_TOKEN`, configura el mismo valor en `token`.
- El token queda almacenado en `shell.json`; conserva ese archivo con permisos `600`.
- El plugin entrega el token al colector por entrada estándar, nunca como argumento de proceso.
- `curl` lo lee desde un archivo temporal con permisos `600`, eliminado al terminar.
- Para evitar filtraciones, un token solo se envía por HTTPS o a una dirección loopback (`localhost`, `127.0.0.1`, `::1`).
- No publiques RackWatch directamente en Internet. Prefiere HTTPS detrás de un proxy autenticado, VPN o túnel seguro.
- RackWatch puede controlar Docker. Mantén su denylist/allowlist y protege el API con token.

El plugin no incorpora telemetría ni envía información a terceros. Solo se conecta a la URL RackWatch configurada. Los nombres de hosts, contenedores y alertas recibidos se mantienen en memoria para dibujar el panel.

## Uso

- **Clic izquierdo:** Abrir o cerrar el panel desplegable.
- **Clic derecho o central:** Forzar actualización inmediata de métricas.
- **`R` / `r`:** Actualizar desde el teclado mientras el panel está activo.
- **`Esc`:** Cerrar el panel o cancelar el diálogo de confirmación.
- **`Tab`:** Alternar entre paneles; dentro del diálogo de confirmación cambia entre *Cancelar* y *Reiniciar*.
- **`Enter`:** Ejecutar la opción seleccionada en el diálogo de confirmación.
- **Botón `󰑓`:** Solicitar reinicio del contenedor (abre diálogo de seguridad).
- **Botón `Ack`:** Confirmar y silenciar una alerta en RackWatch.

## Solución de problemas

### El widget aparece como offline

1. Comprueba el endpoint desde el escritorio:

   ```bash
   curl -fsS http://SERVIDOR:PUERTO/healthz
   ```

2. Verifica el puerto publicado (`8080` normal, frecuentemente `8180` en CasaOS).
3. Si el API responde `401`, configura el token correcto.
4. Si utilizas token con un servidor remoto, configura HTTPS.
5. Revisa los mensajes recientes:

   ```bash
   journalctl --user --since today --no-pager | grep -i rackwatch
   ```

### Una acción falla

El panel muestra el error devuelto por RackWatch. Las causas más comunes son token inválido, contenedor protegido por la denylist, Docker inaccesible o nombre no permitido por la allowlist.

## Validación para desarrollo

```bash
omarchy plugin validate ~/.config/omarchy/plugins/nezbit.rackwatch
bash -n ~/.config/omarchy/plugins/nezbit.rackwatch/collector.sh
~/.config/omarchy/plugins/nezbit.rackwatch/tests/test-collector.sh
```

## Privacidad

El código no contiene correos, nombres reales, tokens ni rutas personales. La única identidad pública incluida es `NezbiT`, como autor y propietario del repositorio RackWatch.

## Licencia

MIT © NezbiT. Consulta [LICENSE](LICENSE).
