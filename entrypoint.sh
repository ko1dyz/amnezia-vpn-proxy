#!/usr/bin/env bash
set -euo pipefail

IFACE=awg0
SRC=/config/amnezia.conf
DST=/etc/amnezia/amneziawg/${IFACE}.conf

[[ -f $SRC ]] || { echo "[!] Missing VPN configuration: $SRC"; exit 1; }
mkdir -p /etc/amnezia/amneziawg
# Remove DNS: resolvconf is unavailable; proxy resolvers are set in 3proxy.cfg.
grep -viE '^\s*DNS\s*=' "$SRC" > "$DST"
chmod 600 "$DST"

# awg-quick uses amneziawg-go when the kernel module is unavailable.
awg-quick up "$IFACE"

# IPv4 kill switch: allow the tunnel, its marked packets, local destinations, and established flows.
FWMARK=$(awg show "$IFACE" fwmark)
iptables -I OUTPUT ! -o "$IFACE" -m mark ! --mark "$FWMARK" \
  -m addrtype ! --dst-type LOCAL \
  -m conntrack ! --ctstate ESTABLISHED,RELATED -j REJECT

cleanup() { awg-quick down "$IFACE" || true; }
trap cleanup EXIT INT TERM

echo "[+] Tunnel is up. Outbound IP details:"
curl -s --max-time 10 https://ipinfo.io/json || echo "(Unable to check the outbound IP)"
echo

exec 3proxy /etc/3proxy/3proxy.cfg
