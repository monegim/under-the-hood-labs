#!/usr/bin/env bash
# Lab 9 (VXLAN) — tears down and redeploys the topology, then re-applies
# the README's Steps 1-5 live config (underlay addressing, VXLAN device
# creation, FDB wildcard entries, bridging) — none of this is baked into
# the topology file.
set -uo pipefail

LAB="vxlan-lab"
HOSTA="clab-${LAB}-hostA"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
HOSTB="clab-${LAB}-hostB"

cd "$(dirname "$0")"

echo "[reset] destroying existing topology (if any)..."
sudo containerlab destroy -t topology.clab.yml --cleanup

echo "[reset] deploying topology..."
sudo containerlab deploy -t topology.clab.yml

echo "[reset] waiting for nodes to be ready..."
for c in "$HOSTA" "$R1" "$R2" "$HOSTB"; do
  ready=0
  for i in $(seq 1 30); do
    docker exec "$c" true >/dev/null 2>&1 && { ready=1; break; }
    sleep 2
  done
  [ "$ready" -eq 1 ] || { echo "[reset] ERROR: $c never became ready"; exit 1; }
done

echo "[reset] installing tools (this can take a minute)..."
for n in hostA r1 r2 hostB; do
  docker exec "clab-${LAB}-$n" bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump >/dev/null"
done

echo "[reset] addressing the underlay and the hosts..."
docker exec "$R1" ip addr add 172.16.0.1/30 dev eth2
docker exec "$R1" ip link set eth2 up

docker exec "$R2" ip addr add 172.16.0.2/30 dev eth1
docker exec "$R2" ip link set eth1 up

docker exec "$HOSTA" ip addr add 10.0.0.10/24 dev eth1
docker exec "$HOSTA" ip link set eth1 up

docker exec "$HOSTB" ip addr add 10.0.0.20/24 dev eth1
docker exec "$HOSTB" ip link set eth1 up

echo "[reset] creating the VXLAN interfaces (VNI 10, no default remote)..."
docker exec "$R1" ip link add vxlan10 type vxlan id 10 dstport 4789 local 172.16.0.1 dev eth2
docker exec "$R1" ip link set vxlan10 up

docker exec "$R2" ip link add vxlan10 type vxlan id 10 dstport 4789 local 172.16.0.2 dev eth1
docker exec "$R2" ip link set vxlan10 up

echo "[reset] programming the wildcard FDB entries..."
docker exec "$R1" bridge fdb append 00:00:00:00:00:00 dev vxlan10 dst 172.16.0.2
docker exec "$R2" bridge fdb append 00:00:00:00:00:00 dev vxlan10 dst 172.16.0.1

echo "[reset] bridging vxlan10 to the local host-facing link..."
docker exec "$R1" ip link add br0 type bridge
docker exec "$R1" ip link set br0 up
docker exec "$R1" ip link set eth1 master br0
docker exec "$R1" ip link set eth1 up
docker exec "$R1" ip link set vxlan10 master br0

docker exec "$R2" ip link add br0 type bridge
docker exec "$R2" ip link set br0 up
docker exec "$R2" ip link set eth2 master br0
docker exec "$R2" ip link set eth2 up
docker exec "$R2" ip link set vxlan10 master br0

echo "[reset] verifying end-to-end connectivity..."
if docker exec "$HOSTA" ping -c 2 -W 2 10.0.0.20 >/dev/null 2>&1; then
  echo "[reset] hostA -> hostB reachable, VXLAN overlay is healthy"
else
  echo "[reset] WARNING: hostA -> hostB ping failed, check manually"
fi

echo "[reset] done. Run ./check.sh to verify health."
