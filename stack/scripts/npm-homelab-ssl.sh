#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
set -a
# shellcheck disable=SC1091
source .env
set +a

LAN_IP="${LAN_IP:?Define LAN_IP en stack/.env}"
LOCAL_DOMAIN="${LOCAL_DOMAIN:-homelab}"
NPM_URL="${NPM_URL:-http://${LAN_IP}:81}"
NPM_EMAIL="${NPM_EMAIL:?Exporta NPM_EMAIL}"
NPM_PASSWORD="${NPM_PASSWORD:?Exporta NPM_PASSWORD (cuenta de http://LAN_IP:81)}"

CERT_DIR="$ROOT/npm/certs/homelab"
CRT="$CERT_DIR/homelab.crt"
KEY="$CERT_DIR/homelab.key"

mkdir -p "$CERT_DIR"
if [[ ! -f "$CRT" ]]; then
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout "$KEY" -out "$CRT" \
    -subj "/CN=${LOCAL_DOMAIN} Local" \
    -addext "subjectAltName=DNS:${LOCAL_DOMAIN},DNS:*.${LOCAL_DOMAIN}"
fi

login_json=$(curl -sS -X POST "$NPM_URL/api/tokens" \
  -H 'Content-Type: application/json' \
  -d "$(NPM_EMAIL="$NPM_EMAIL" NPM_PASSWORD="$NPM_PASSWORD" python3 -c 'import json,os; print(json.dumps({"identity":os.environ["NPM_EMAIL"],"secret":os.environ["NPM_PASSWORD"]}))')")

token=$(echo "$login_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("token") or "")')
if [[ -z "$token" ]]; then
  echo "Login a NPM falló: $login_json" >&2
  exit 1
fi

auth="Authorization: Bearer $token"
nice_name="${LOCAL_DOMAIN}-local-ca"

cert_id=$(curl -sS "$NPM_URL/api/nginx/certificates" -H "$auth" | python3 -c "
import json,sys
for c in json.load(sys.stdin):
    if c.get('nice_name')=='$nice_name':
        print(c['id']); break
")

if [[ -z "$cert_id" ]]; then
  cert_id=$(curl -sS -X POST "$NPM_URL/api/nginx/certificates" -H "$auth" -H 'Content-Type: application/json' \
    -d "{\"provider\":\"other\",\"nice_name\":\"$nice_name\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  curl -sS -X POST "$NPM_URL/api/nginx/certificates/$cert_id/upload" -H "$auth" \
    -F "certificate=@$CRT" -F "certificate_key=@$KEY" >/dev/null
  echo "Certificado creado y subido (id=$cert_id)."
else
  curl -sS -X POST "$NPM_URL/api/nginx/certificates/$cert_id/upload" -H "$auth" \
    -F "certificate=@$CRT" -F "certificate_key=@$KEY" >/dev/null || true
  echo "Usando certificado existente id=$cert_id."
fi

NPM_URL="$NPM_URL" TOKEN="$token" CERT_ID="$cert_id" python3 <<'PY'
import json, os, urllib.request, urllib.error

PUT_KEYS = (
    "domain_names", "forward_scheme", "forward_host", "forward_port",
    "access_list_id", "certificate_id", "ssl_forced", "caching_enabled",
    "block_exploits", "allow_websocket_upgrade", "http2_support",
    "hsts_enabled", "hsts_subdomains", "advanced_config", "meta", "locations", "enabled",
)

base, token, cert_id = os.environ["NPM_URL"], os.environ["TOKEN"], int(os.environ["CERT_ID"])
req = urllib.request.Request(f"{base}/api/nginx/proxy-hosts", headers={"Authorization": f"Bearer {token}"})
hosts = json.load(urllib.request.urlopen(req))
for h in hosts:
    if h.get("is_deleted"):
        continue
    payload = {k: h[k] for k in PUT_KEYS if k in h}
    payload["certificate_id"] = cert_id
    payload["meta"] = {
        "letsencrypt_agree": False,
        "dns_challenge": False,
    }
    payload.setdefault("http2_support", True)
    hid = h["id"]
    put = urllib.request.Request(
        f"{base}/api/nginx/proxy-hosts/{hid}",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="PUT",
    )
    with urllib.request.urlopen(put) as r:
        body = json.load(r)
        print(f"SSL: {body['domain_names'][0]} OK")
PY

echo "Listo. ./scripts/check-domains.sh"
