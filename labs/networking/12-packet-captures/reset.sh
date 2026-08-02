#!/usr/bin/env bash
# Lab 12 (Packet Captures) — tears down and redeploys the topology, then
# re-applies the README's Steps 1-2 live config (addressing, forwarding,
# starting the HTTP listener on the server) — none of this is baked into
# the topology file. This restores the clean baseline (no firewall rules,
# listener up) so the two challenges can be re-run from scratch.
set -uo pipefail

LAB="pcap-lab"
CLIENT="clab-${LAB}-client"
R1="clab-${LAB}-r1"
SERVER="clab-${LAB}-server"

cd "$(dirname "$0")"

echo "[reset] destroying existing topology (if any)..."
sudo containerlab destroy -t topology.clab.yml --cleanup

echo "[reset] deploying topology..."
sudo containerlab deploy -t topology.clab.yml

echo "[reset] waiting for nodes to be ready..."
for c in "$CLIENT" "$R1" "$SERVER"; do
  ready=0
  for i in $(seq 1 30); do
    docker exec "$c" true >/dev/null 2>&1 && { ready=1; break; }
    sleep 2
  done
  [ "$ready" -eq 1 ] || { echo "[reset] ERROR: $c never became ready"; exit 1; }
done

echo "[reset] installing tools (this can take a minute)..."
docker exec "$CLIENT" bash -c \
  "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump tshark python3 curl >/dev/null"
docker exec "$SERVER" bash -c \
  "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump tshark python3 curl >/dev/null"
docker exec "$R1" bash -c \
  "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump iptables >/dev/null"

echo "[reset] addressing interfaces and enabling forwarding..."
docker exec "$CLIENT" ip addr add 10.0.1.10/24 dev eth1
docker exec "$CLIENT" ip link set eth1 up
docker exec "$CLIENT" ip route add default via 10.0.1.1

docker exec "$R1" ip addr add 10.0.1.1/24 dev eth1
docker exec "$R1" ip link set eth1 up
docker exec "$R1" ip addr add 10.0.2.1/24 dev eth2
docker exec "$R1" ip link set eth2 up
docker exec "$R1" sysctl -w net.ipv4.ip_forward=1

docker exec "$SERVER" ip addr add 10.0.2.10/24 dev eth1
docker exec "$SERVER" ip link set eth1 up
docker exec "$SERVER" ip route add default via 10.0.2.1

echo "[reset] starting the HTTP listener on the server..."
docker exec -d "$SERVER" python3 -m http.server 8080 --bind 0.0.0.0
sleep 1

echo "[reset] verifying end-to-end connectivity..."
if docker exec "$CLIENT" curl -s --max-time 5 http://10.0.2.10:8080/ -o /dev/null; then
  echo "[reset] client -> server:8080 reachable"
else
  echo "[reset] WARNING: client -> server:8080 curl failed, check manually"
fi

echo "[reset] done. Run ./check.sh to verify health."
