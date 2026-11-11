# Dominios locales con NPM + AdGuard

Accede a los servicios con nombres (`http://panel.homelab`) en lugar de `IP:puerto`. NPM escucha en **80/443**; AdGuard resuelve `*.homelab` hacia la IP del servidor.

## 1. Requisitos en la red

1. En el **router** (o en cada PC), DNS primario = `<LAN_IP>` (AdGuard; coincide con `LAN_IP` en `.env`).
2. `LOCAL_DOMAIN=homelab` y `LAN_IP` en [stack/.env](../.env).

## 2. Primer acceso a Nginx Proxy Manager (obligatorio)

Abre **http://<LAN_IP>:81**

Si la API responde `"setup": false`, **no** sirve `admin@example.com` / `changeme`. En la primera visita el propio NPM pide **crear** el usuario administrador (correo + contraseña).

Comprueba el estado:

```bash
curl -s http://<LAN_IP>:81/api/ | jq
# Tras registrarte: "setup": true
```

## 3. Reescrituras DNS en AdGuard

Opción automática (ya aplica `homelab` y `*.homelab` → `LAN_IP` si ejecutaste el script):

```bash
cd stack
./scripts/configure-local-domains.sh
# Sin NPM_EMAIL/NPM_PASSWORD solo actualiza AdGuard
```

Manual en **http://<LAN_IP>:3000** → *Filters* → *DNS rewrites*:

| Domain | Answer |
|--------|--------|
| `homelab` | `<LAN_IP>` |
| `*.homelab` | `<LAN_IP>` |

## 4. Proxy hosts en NPM

En **Hosts → Proxy Hosts → Add Proxy Host** (esquema **http** hacia el contenedor en la red `proxy`):

| Domain | Forward host | Port | Notas |
|--------|----------------|------|--------|
| `npm.homelab` | `npm` | `81` | Panel de NPM por nombre |
| `adguard.homelab` | `adguard` | `80` | UI interna del contenedor |
| `panel.homelab` | `panel` | `80` | Pterodactyl |
| `portainer.homelab` | `portainer` | `9443` | Scheme **https**, websockets on |

Automático tras crear el admin:

```bash
export NPM_EMAIL='tu@correo'
export NPM_PASSWORD='tu-contraseña'
./scripts/configure-local-domains.sh
```

## 5. HTTPS local (opcional)

Para la LAN, con certificado autofirmado: en cada Proxy Host → pestaña **SSL** → *Request a new SSL Certificate* solo funciona si el dominio es público y el puerto 80 es alcanzable desde Internet.

En homelab sin dominio real:

- Usa **HTTP** (`http://panel.homelab`), o
- **Custom certificate** (CA propia / mkcert) en NPM, o
- Deja `portainer.homelab` con backend HTTPS y acepta el aviso del navegador.

## 6. Dominio público + Let's Encrypt (futuro)

1. Dominio real con registro **A** hacia tu IP pública.
2. Port forwarding **80** y **443** al host.
3. En NPM, SSL con Let's Encrypt en cada Proxy Host.
4. Opcional: reescritura DNS en AdGuard solo para uso interno (split DNS).

## 7. Comprobaciones

```bash
# Debe responder la IP del servidor
dig +short panel.homelab @<LAN_IP>

# Debe abrir el panel vía NPM
curl -sI http://panel.homelab | head -3
```

## 8. Fallos frecuentes

| Síntoma | Causa |
|---------|--------|
| Login NPM inválido con `changeme` | No completaste el registro inicial (`setup: false`) |
| El nombre no resuelve | Cliente no usa AdGuard como DNS |
| 502 Bad Gateway | `forward_host` incorrecto; usa nombre de servicio Docker (`panel`, `adguard`) |
| AdGuard en :3000 no carga | El compose debe mapear `3000:80` (UI interna en puerto 80) |

## 9. Error 404 (o página en blanco) en cada dominio

En el servidor, **HTTP en el puerto 80 funciona** si el DNS apunta a AdGuard. El fallo habitual es el **HTTPS automático** del navegador:

| Prueba | Resultado esperado si falla HTTPS |
|--------|-----------------------------------|
| `http://panel.homelab` | Debe abrir (200) |
| `https://panel.homelab` | Falla hasta tener certificado en NPM (000 / conexión rechazada) |

**Qué hacer:**

1. Prueba primero con **`http://`** explícito (no dejes que el navegador añada `https://`).
2. Confirma DNS en el **equipo donde navegas** (no solo en el servidor):

   ```bash
   ./scripts/check-domains.sh
   ```

3. Activa HTTPS local con certificado autofirmado:

   ```bash
   export NPM_PASSWORD='tu-contraseña-de-NPM'
   ./scripts/npm-homelab-ssl.sh
   ```

   Acepta la advertencia del navegador o importa `npm/certs/homelab/homelab.crt` como CA de confianza.

4. Si el DNS muestra **SIN RESPUESTA**, ese cliente **no está usando AdGuard**: configura DNS manual a `LAN_IP` o DNS del router → `LAN_IP`. Desactiva **DNS over HTTPS** en Firefox/Chrome.

5. `APP_URL` del panel debe coincidir con el dominio: `http://panel.homelab` en `.env`.

## 10. `ERR_NAME_NOT_RESOLVED` en el navegador

El servidor puede responder bien mientras **este equipo** sigue usando otro DNS (p. ej. el del router). Comprueba:

```bash
getent hosts panel.<LOCAL_DOMAIN>
```

Si no resuelve:

- Configura DNS del sistema → `<LAN_IP>`, o
- Ejecuta `./scripts/usar-dns-adguard-en-esta-pc.sh` (NetworkManager), o
- Añade entradas en `/etc/hosts` solo para pruebas locales.

Diagnóstico: `./scripts/diagnostico-cliente.sh`
