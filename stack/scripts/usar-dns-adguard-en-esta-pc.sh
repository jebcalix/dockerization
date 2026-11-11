#!/usr/bin/env bash
# Usar AdGuard (LAN_IP) como DNS en la conexión Wi‑Fi activa — Manjaro/NetworkManager
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/.env"
LAN_IP="${LAN_IP:?}"

CONN=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: '$2!="lo"{print $1; exit}')
if [[ -z "$CONN" ]]; then
  echo "No hay conexión activa distinta de lo." >&2
  exit 1
fi

echo "Conexión: $CONN → DNS $LAN_IP"
sudo nmcli connection modify "$CONN" ipv4.dns "$LAN_IP" ipv4.ignore-auto-dns yes
sudo nmcli connection up "$CONN"

echo ""
echo "Comprueba:"
getent hosts panel.homelab || true
echo "Abre: https://panel.homelab (acepta certificado autofirmado la primera vez)"
