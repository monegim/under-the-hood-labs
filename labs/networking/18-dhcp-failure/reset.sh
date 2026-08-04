#!/usr/bin/env bash
# Lab 18 (DHCP Failure) — destroys and redeploys the topology, then
# re-applies the README's Steps 1-3 live config (package install,
# addressing, a clean dnsmasq DHCP server, and an initial lease for the
# client) — none of this is baked into the topology file.
set -uo pipefail

LAB="dhcp-lab"
CLIENT="clab-${LAB}-client"
DHCPSERVER="clab-${LAB}-dhcp-server"

cd "$(dirname "$0")"

echo "[reset] destroying existing topology (if any)..."
sudo containerlab destroy -t topology.clab.yml --cleanup

echo "[reset] deploying topology..."
sudo containerlab deploy -t topology.clab.yml

echo "[reset] waiting for nodes to be ready..."
for c in "$CLIENT" "$DHCPSERVER"; do
  ready=0
  for i in $(seq 1 30); do
    docker exec "$c" true >/dev/null 2>&1 && { ready=1; break; }
    sleep 2
  done
  [ "$ready" -eq 1 ] || { echo "[reset] ERROR: $c never became ready"; exit 1; }
done

echo "[reset] installing tools (this can take a minute)..."
docker exec "$CLIENT" bash -c \
  "apt-get update -qq && apt-get install -y -qq iproute2 isc-dhcp-client >/dev/null"
docker exec "$DHCPSERVER" bash -c \
  "apt-get update -qq && apt-get install -y -qq iproute2 dnsmasq iputils-ping >/dev/null"

echo "[reset] addressing the DHCP server..."
docker exec "$DHCPSERVER" ip addr add 10.50.0.1/24 dev eth1
docker exec "$DHCPSERVER" ip link set eth1 up

docker exec "$CLIENT" ip link set eth1 up

echo "[reset] clearing any leftover lease state and starting a clean DHCP server..."
docker exec "$DHCPSERVER" pkill dnsmasq 2>/dev/null || true
docker exec "$DHCPSERVER" bash -c "rm -f /var/lib/misc/dnsmasq.leases"
sleep 1
docker exec -d "$DHCPSERVER" dnsmasq -k --no-resolv --no-hosts \
  --interface=eth1 --bind-interfaces \
  --dhcp-range=10.50.0.100,10.50.0.101,2m \
  --dhcp-leasefile=/var/lib/misc/dnsmasq.leases --log-dhcp

echo "[reset] obtaining an initial lease on the client..."
docker exec "$CLIENT" dhclient -r eth1 >/dev/null 2>&1 || true
sleep 1
if docker exec "$CLIENT" dhclient -v eth1 2>&1 | grep -q "DHCPACK"; then
  echo "[reset] client obtained a lease"
else
  echo "[reset] WARNING: client did not obtain a lease, check manually"
fi

echo "[reset] done. Run ./check.sh to verify health."
