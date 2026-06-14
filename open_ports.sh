#!/usr/bin/env bash
# Open firewall ports for the CAPTCHA solver on a Linux VPS.
# Supports UFW (Debian/Ubuntu), firewalld (RHEL/CentOS), and iptables fallback.
#
# Usage:
#   sudo bash open_ports.sh                 # read PORTS from .env
#   sudo bash open_ports.sh 5032 5033 5040  # explicit ports
set -euo pipefail

cd "$(dirname "$0")"

PORTS=("$@")
if [ ${#PORTS[@]} -eq 0 ]; then
  if command -v python3 >/dev/null 2>&1; then
    PARSED="$(python3 - <<'PY'
import os
try:
    from dotenv import dotenv_values
    v = dotenv_values('.env')
except Exception:
    v = {}
raw = v.get('PORTS', '')
out = []
for p in raw.replace(' ', '').split(','):
    if not p:
        continue
    if '-' in p:
        a, b = p.split('-'); out += list(range(int(a), int(b) + 1))
    else:
        out.append(int(p))
if not out:
    ps = int(v.get('PORT_START', v.get('PORT', '5032')))
    pc = int(v.get('PORT_COUNT', '1'))
    out = list(range(ps, ps + pc))
print(' '.join(map(str, out)))
PY
)"
    read -r -a PORTS <<< "$PARSED"
  fi
fi

if [ ${#PORTS[@]} -eq 0 ]; then
  echo "Could not determine ports. Usage: sudo bash open_ports.sh 5032 5033 ..."
  exit 1
fi

echo "Ports to open: ${PORTS[*]}"
echo

if command -v ufw >/dev/null 2>&1; then
  echo "==> Using UFW"
  for p in "${PORTS[@]}"; do ufw allow "$p"/tcp; done
  echo
  ufw status numbered || true
  exit 0
fi

if command -v firewall-cmd >/dev/null 2>&1; then
  echo "==> Using firewalld"
  for p in "${PORTS[@]}"; do
    firewall-cmd --permanent --add-port="$p"/tcp
  done
  firewall-cmd --reload
  echo
  firewall-cmd --list-ports
  exit 0
fi

if command -v iptables >/dev/null 2>&1; then
  echo "==> Using iptables"
  for p in "${PORTS[@]}"; do
    iptables -I INPUT -p tcp --dport "$p" -j ACCEPT
  done
  echo
  iptables -nL INPUT | head -40
  echo
  echo "NOTE: rules are not persistent yet. Persist with your distro tool, e.g.:"
  echo "  Debian/Ubuntu:  apt-get install iptables-persistent && netfilter-persistent save"
  echo "  RHEL/CentOS:    yum install iptables-services && service iptables save"
  exit 0
fi

echo "No supported firewall found (ufw / firewalld / iptables). Nothing to do."
exit 1
