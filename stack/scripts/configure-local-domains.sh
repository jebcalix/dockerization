#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

LAN_IP="${LAN_IP:?Define LAN_IP en stack/.env}"
LOCAL_DOMAIN="${LOCAL_DOMAIN:-homelab}"
NPM_URL="${NPM_URL:-http://${LAN_IP}:81}"
AGH_CONF="$ROOT/adguard/conf/AdGuardHome.yaml"

echo "Dominio local: *.${LOCAL_DOMAIN} -> ${LAN_IP}"

if [[ ! -f "$AGH_CONF" ]]; then
  echo "No existe $AGH_CONF — completa primero el asistente de AdGuard." >&2
  exit 1
fi

docker compose stop adguard
LOCAL_DOMAIN="$LOCAL_DOMAIN" LAN_IP="$LAN_IP" AGH_CONF="$AGH_CONF" python3 <<'PY'
import os
from pathlib import Path
path = Path(os.environ["AGH_CONF"])
domain = os.environ["LOCAL_DOMAIN"]
ip = os.environ["LAN_IP"]
text = path.read_text()
if f"domain: {domain}" in text or f'domain: "{domain}"' in text:
    print("AdGuard: rewrites ya presentes, sin cambios.")
else:
    needle = "  rewrites: []"
    if needle not in text:
        raise SystemExit("No se encontró '  rewrites: []' en AdGuardHome.yaml")
    block = f"""  rewrites:
    - domain: {domain}
      answer: {ip}
      enabled: true
    - domain: '*.{domain}'
      answer: {ip}
      enabled: true"""
    path.write_text(text.replace(needle, block, 1))
    print("AdGuard: rewrites actualizados.")
PY
docker compose start adguard

if [[ -z "${NPM_EMAIL:-}" || -z "${NPM_PASSWORD:-}" ]]; then
  echo ""
  echo "NPM: crea el admin en ${NPM_URL} (setup inicial)."
  echo "Después: export NPM_EMAIL=... NPM_PASSWORD=... y vuelve a ejecutar este script."
  exit 0
fi

token="$(curl -sf "$NPM_URL/api/tokens" \
  -H 'Content-Type: application/json' \
  -d "{\"identity\":\"$NPM_EMAIL\",\"secret\":\"$NPM_PASSWORD\"}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("token") or "")')"

if [[ -z "$token" ]]; then
  echo "No se pudo obtener token de NPM. ¿Completaste el registro en $NPM_URL ?" >&2
  exit 1
fi

create_host() {
  local name="$1" host="$2" port="$3" scheme="${4:-http}"
  local domain="${name}.${LOCAL_DOMAIN}"
  local payload
  payload=$(DOMAIN="$domain" HOST="$host" PORT="$port" SCHEME="$scheme" python3 <<'EOF'
import json, os
print(json.dumps({
  "domain_names": [os.environ["DOMAIN"]],
  "forward_scheme": os.environ["SCHEME"],
  "forward_host": os.environ["HOST"],
  "forward_port": int(os.environ["PORT"]),
  "access_list_id": 0,
  "certificate_id": 0,
  "ssl_forced": False,
  "caching_enabled": False,
  "block_exploits": True,
  "allow_websocket_upgrade": True,
  "http2_support": False,
  "hsts_enabled": False,
  "hsts_subdomains": False,
  "meta": {"letsencrypt_agree": False, "dns_challenge": False},
  "advanced_config": "",
  "locations": [],
  "enabled": True,
}))
EOF
)
  http_code=$(curl -s -o /tmp/npm-create.json -w '%{http_code}' \
    -X POST "$NPM_URL/api/nginx/proxy-hosts" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    -d "$payload")
  if [[ "$http_code" == "201" ]]; then
    echo "NPM: $domain -> $scheme://$host:$port"
  else
    echo "NPM: fallo $domain (HTTP $http_code): $(cat /tmp/npm-create.json)" >&2
  fi
}

create_host npm npm 81 http
create_host adguard adguard 80 http
create_host portainer portainer 9443 https
create_host panel panel 80 http

echo ""
echo "Listo. Ejemplos: http://panel.${LOCAL_DOMAIN}  http://adguard.${LOCAL_DOMAIN}"
