#!/usr/bin/env bash
# Lab 20 (NAT Port Exhaustion) - destroys and redeploys the topology, then
# re-applies addressing, ip_forward, the listener, and the FULL Step 1-7
# build (ending at the healthy dual-IP fix, not the intentionally-narrow
# Step 4 state) - none of this is baked into the topology file.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOST_INT="clab-natexh-host-int"
ROUTER="clab-natexh-router"
HOST_EXT="clab-natexh-host-ext"

echo "[reset] destroying existing topology (if any)..."
sudo containerlab destroy -t "$DIR/topology.clab.yml" --cleanup

echo "[reset] deploying topology fresh..."
sudo containerlab deploy -t "$DIR/topology.clab.yml"

echo "[reset] addressing everything..."
docker exec "$HOST_INT" ip addr add 192.168.50.10/24 dev eth1
docker exec "$HOST_INT" ip link set eth1 up
docker exec "$HOST_INT" ip route add default via 192.168.50.1

docker exec "$ROUTER" ip addr add 192.168.50.1/24 dev eth1
docker exec "$ROUTER" ip link set eth1 up
docker exec "$ROUTER" ip addr add 203.0.113.1/24 dev eth2
docker exec "$ROUTER" ip link set eth2 up
docker exec "$ROUTER" ip addr add 203.0.113.21/24 dev eth2

docker exec "$HOST_EXT" ip addr add 203.0.113.20/24 dev eth1
docker exec "$HOST_EXT" ip link set eth1 up

echo "[reset] enabling ip_forward on router..."
docker exec "$ROUTER" sysctl -w net.ipv4.ip_forward=1

echo "[reset] installing socat + conntrack-tools..."
docker exec "$HOST_EXT" apk add --no-cache socat >/dev/null
docker exec "$ROUTER" apk add --no-cache conntrack-tools >/dev/null

echo "[reset] starting listener on host-ext:9000..."
docker exec -d "$HOST_EXT" socat TCP-LISTEN:9000,fork,reuseaddr SYSTEM:'cat'

echo "[reset] applying the dual-IP SNAT fix (README Step 7 end state)..."
docker exec "$ROUTER" iptables -t nat -A POSTROUTING -o eth2 \
  -s 192.168.50.0/24 -m statistic --mode nth --every 2 --packet 0 \
  -j SNAT --to-source 203.0.113.1:40000-40004
docker exec "$ROUTER" iptables -t nat -A POSTROUTING -o eth2 \
  -s 192.168.50.0/24 -j SNAT --to-source 203.0.113.21:40000-40004

echo "[reset] Lab 20 topology redeployed at the healthy (Step 7) end state."
echo "[reset] Run ./check.sh to verify, or replay Steps 4-6 manually to see the narrow-pool exhaustion first."
