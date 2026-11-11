# Stack homelab local

Servicios en una sola máquina: **AdGuard Home**, **Nginx Proxy Manager**, **Portainer** y **Pterodactyl** (panel + MariaDB + Redis + Wings), accesibles por IP de la LAN.

No levantar junto con [homelab/docker-compose.yml](../homelab/docker-compose.yml) (Pi-hole compite por 53, 80 y 443).

## Requisitos

- Docker y Docker Compose v2+
- Variables en `stack/.env` (parte de `.env.example`; las contraseñas reales **no** van al repositorio)

## Puertos y URLs (sustituye `<LAN_IP>` por el valor de `.env`)

| Servicio | URL / puerto |
|----------|----------------|
| Nginx Proxy Manager (admin) | `http://<LAN_IP>:81` — primer login: `admin@example.com` / `changeme` |
| AdGuard Home (asistente / UI) | `http://<LAN_IP>:3000` |
| Portainer | `https://<LAN_IP>:9443` |
| Pterodactyl panel | `http://<LAN_IP>:8020` |
| Wings (API daemon) | `http://<LAN_IP>:8080` |
| Wings SFTP | `<LAN_IP>:2022` |
| NPM HTTP/HTTPS | `80` / `443` |
| AdGuard DNS | `53` tcp+udp |

Si cambia la IP de la máquina, actualiza `LAN_IP` y `APP_URL` en `.env`.

## Arranque rápido (infra + panel nuevo)

Desde este directorio:

```bash
cd stack

# 1) DNS, proxy, Portainer
docker compose up -d adguard npm portainer

# 2) Base del panel
docker compose up -d database cache
docker compose run --rm panel php artisan migrate --seed --force --no-interaction
docker compose run --rm panel php artisan p:user:make
docker compose up -d panel
```

**Guarda `APP_KEY`** (y el resto de claves) de `stack/pterodactyl/var/.env`. Sin `APP_KEY` no se recuperan datos cifrados del panel.

## AdGuard Home — asistente inicial

1. Abre `http://<LAN_IP>:3000`.
2. Interfaz de administración: deja el puerto **3000** (no uses 80 ni 443; los usa NPM).
3. DNS del servidor: puerto **53**.
4. En el router o en cada cliente, apunta el DNS a `<LAN_IP>` para filtrar en toda la LAN.

### DNS en puerto 53 (`systemd-resolved`)

En Manjaro/Arch, `systemd-resolved` usa el stub en `127.0.0.53`. Publicar `53:53` en `0.0.0.0` suele fallar con *address already in use*. El compose enlaza DNS solo a `LAN_IP` (p. ej. `<LAN_IP>:53`), que es lo que deben usar los clientes de la LAN.

### Si aún no puede escuchar en 53

En el host (solo si falla el bind con `LAN_IP`):

```bash
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sudo sed -i 's/DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
grep -q DNSStubListener /etc/systemd/resolved.conf || echo 'DNSStubListener=no' | sudo tee -a /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved
```

Reinicia el stack de AdGuard después.

## NPM (sin dominio por ahora)

Cada servicio se abre por **IP:puerto**. NPM queda listo para publicar sitios en 80/443.

Más adelante, con nombres locales:

1. En AdGuard: **Filters → DNS rewrites** (p. ej. `*.homelab` → `LAN_IP`).
2. En NPM: **Proxy Hosts** hacia el puerto interno del servicio.

## Pterodactyl — Wings en este host

1. Inicia sesión en el panel (`http://<LAN_IP>:8020`).
2. **Admin → Nodes → Create new**:
   - **Name**: el que quieras
   - **FQDN**: valor de `LAN_IP` (solo IP, sin `https://`)
   - **Communicate over HTTPS**: desactivado (acceso por HTTP en LAN)
   - **Daemon port**: `8080`
   - **Daemon SFTP port**: `2022`
   - Memoria / disco según tu hardware
3. Tras crear el nodo, en la ficha del nodo usa **Configuration** y copia el `config.yml` generado a:

   `stack/wings/etc/config.yml`

4. Crea en el host las rutas de Wings si no existen:

   ```bash
   sudo mkdir -p /var/lib/pterodactyl /var/log/pterodactyl /tmp/pterodactyl /run/wings
   ```

5. Levanta Wings:

   ```bash
   docker compose --profile wings up -d
   ```

6. En el panel, marca el nodo como disponible y crea servidores de juego; Wings publicará los puertos de juego al asignarlos.

Los datos de servidores viven en `/var/lib/pterodactyl` del host (fuera del repo).

## Imágenes fijadas

| Servicio | Imagen |
|----------|--------|
| Panel | `ghcr.io/pterodactyl/panel:v1.15.2` |
| Wings | `ghcr.io/pterodactyl/wings:v1.13.4` |
| MariaDB | `mariadb:11.4` |
| Redis | `redis:7-alpine` |

No uses el panel 2.x en beta para producción; `latest` puede cambiar de versión mayor.

## Comandos útiles

```bash
docker compose ps
docker compose logs -f npm
docker compose down
docker compose --profile wings down
```

## Conflictos con otros stacks del repo

- `bdd/docker-compose.yml` expone MariaDB en `3306` — el panel **no** publica `3306`.
- Pi-hole en `homelab/` usa los mismos puertos críticos que AdGuard/NPM.

## Dominios locales (`panel.homelab`, etc.)

Guía: [docs/dominios-lan.md](docs/dominios-lan.md)

1. Abre **`http://<LAN_IP>:81`** y crea el usuario administrador (la API muestra `"setup": false` hasta entonces; `changeme` no funciona).
2. DNS del router/clientes → IP de AdGuard (`LAN_IP`).
3. Tras el admin: `export NPM_EMAIL=... NPM_PASSWORD=... && ./scripts/configure-local-domains.sh`
