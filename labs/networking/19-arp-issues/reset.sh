#!/usr/bin/env bash
# Lab 19 (ARP Issues) — destroys and redeploys the topology, then
# re-applies the README's Steps 1-3 live config: builds the bridge,
# addresses everyone, puts the VIP on server-a, and lets the client
# resolve it — none of this is baked into the topology file.
set -uo pipefail

LAB="arp-lab"
CLIENT="clab-${LAB}-client"
SWITCH="clab-${LAB}-switch"
SERVER_A="clab-${LAB}-server-a"
SERVER_B="clab-${LAB}-server-b"

cd "$(dirname "$0")"

echo "[reset] destroying existing topology (if any)..."
sudo containerlab destroy -t topology.clab.yml --cleanup

echo "[reset] deploying topology..."
sudo containerlab deploy -t topology.clab.yml

echo "[reset] waiting for nodes to be ready..."
for c in "$CLIENT" "$SWITCH" "$SERVER_A" "$SERVER_B"; do
  ready=0
  for i in $(seq 1 30); do
    docker exec "$c" true >/dev/null 2>&1 && { ready=1; break; }
    sleep 2
  done
  [ "$ready" -eq 1 ] || { echo "[reset] ERROR: $c never became ready"; exit 1; }
done

echo "[reset] installing tools (this can take a minute)..."
for n in "$CLIENT" "$SWITCH" "$SERVER_A" "$SERVER_B"; do
  docker exec "$n" bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping iputils-arping >/dev/null"
done

echo "[reset] building the bridge on switch..."
docker exec "$SWITCH" bash -c "
  ip link add name br0 type bridge
  ip link set br0 up
  ip link set eth1 master br0
  ip link set eth2 master br0
  ip link set eth3 master br0
  ip link set eth1 up
  ip link set eth2 up
  ip link set eth3 up
"

echo "[reset] addressing client and both servers..."
docker exec "$CLIENT" ip addr add 10.0.0.10/24 dev eth1
docker exec "$CLIENT" ip link set eth1 up

docker exec "$SERVER_A" ip addr add 10.0.0.20/24 dev eth1
docker exec "$SERVER_A" ip link set eth1 up

docker exec "$SERVER_B" ip addr add 10.0.0.21/24 dev eth1
docker exec "$SERVER_B" ip link set eth1 up

echo "[reset] ensuring the VIP is only on server-a..."
docker exec "$SERVER_B" ip addr del 10.0.0.100/24 dev eth1 2>/dev/null || true
docker exec "$SERVER_A" ip addr add 10.0.0.100/24 dev eth1 2>/dev/null || true

sleep 1
echo "[reset] verifying the VIP resolves and is reachable..."
if docker exec "$CLIENT" ping -c 2 -W 2 10.0.0.100 >/dev/null 2>&1; then
  echo "[reset] VIP reachable, client's ARP cache primed"
else
  echo "[reset] WARNING: VIP not reachable, check manually"
fi

echo "[reset] done. Run ./check.sh to verify health."
