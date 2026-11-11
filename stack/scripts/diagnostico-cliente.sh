#!/usr/bin/env bash
# Ejecutar en el equipo donde falla la resolución de *.LOCAL_DOMAIN
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/.env" 2>/dev/null || true
LAN_DNS="${1:-${LAN_IP:-}}"
DOMAIN="${2:-${LOCAL_DOMAIN:-homelab}}"
if [[ -z "$LAN_DNS" ]]; then
  echo "Uso: $0 <IP_DNS_AdGuard> [LOCAL_DOMAIN]" >&2
  echo "O define LAN_IP en stack/.env" >&2
  exit 1
fi
echo "=== DNS debe ser $LAN_DNS en el router o en este equipo ==="
for h in panel npm adguard portainer; do
  fqdn="$h.$DOMAIN"
  if command -v dig >/dev/null; then
    dig +short "$fqdn" @"$LAN_DNS" || true
  elif command -v nslookup >/dev/null; then
    nslookup "$fqdn" "$LAN_DNS" 2>/dev/null | tail -2
  else
    echo "Instala dig o nslookup para probar $fqdn"
  fi
done
echo ""
echo "Si no devuelve $LAN_DNS, AdGuard no se usa en ESTE dispositivo."
echo "Prueba en el navegador: https://panel.$DOMAIN (acepta certificado autofirmado si aplica)"
