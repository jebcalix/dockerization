#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/.env" 2>/dev/null || true
LAN_IP="${LAN_IP:?Define LAN_IP en stack/.env}"
LOCAL_DOMAIN="${LOCAL_DOMAIN:-homelab}"

check() {
  local h="$1"
  echo "---- $h ----"
  LAN_IP="$LAN_IP" python3 -c "
import dns.message, dns.query, dns.rdatatype, os
q=dns.message.make_query('$h', dns.rdatatype.A)
r=dns.query.udp(q, os.environ['LAN_IP'], timeout=2)
print('DNS:', [str(rr) for rr in r.answer] if r.answer else 'SIN RESPUESTA (¿usas AdGuard como DNS?)')
"
  code=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --resolve "${h}:80:${LAN_IP}" "http://${h}/" 2>/dev/null || echo ERR)
  echo "HTTP :80 -> $code"
  code=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 3 --resolve "${h}:443:${LAN_IP}" "https://${h}/" 2>/dev/null || echo 000)
  if [[ "$code" == "000" || "$code" == "ERR" ]]; then
    echo "HTTPS :443 -> $code (falta certificado en NPM: ./scripts/npm-homelab-ssl.sh)"
  else
    echo "HTTPS :443 -> $code OK"
  fi
}

for sub in npm adguard panel portainer; do
  check "${sub}.${LOCAL_DOMAIN}"
done
