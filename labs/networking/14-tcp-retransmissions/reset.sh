#!/usr/bin/env bash
# Lab 14 (TCP Retransmissions) — destroys and redeploys the topology, then
# re-applies the README's Step 1 live config (package install, addressing)
# and starts a clean iperf3 server — none of this is baked into the
# topology file. Also guarantees no netem qdisc and no stopped iperf3
# process are left over from a previous challenge run.
set -uo pipefail

LAB="tcp-retrans"
CLIENT="clab-${LAB}-client"
SERVER="clab-${LAB}-server"

cd "$(dirname "$0")"

echo "[reset] destroying existing topology (if any)..."
sudo containerlab destroy -t topology.clab.yml --cleanup

echo "[reset] deploying topology..."
sudo containerlab deploy -t topology.clab.yml

echo "[reset] waiting for nodes to be ready..."
for c in "$CLIENT" "$SERVER"; do
  ready=0
  for i in $(seq 1 30); do
    docker exec "$c" true >/dev/null 2>&1 && { ready=1; break; }
    sleep 2
  done
  [ "$ready" -eq 1 ] || { echo "[reset] ERROR: $c never became ready"; exit 1; }
done

echo "[reset] installing tools (this can take a minute)..."
for n in "$CLIENT" "$SERVER"; do
  docker exec "$n" bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump iperf3 procps >/dev/null"
done

echo "[reset] addressing interfaces..."
docker exec "$CLIENT" ip addr add 10.0.0.10/24 dev eth1
docker exec "$CLIENT" ip link set eth1 up

docker exec "$SERVER" ip addr add 10.0.0.20/24 dev eth1
docker exec "$SERVER" ip link set eth1 up

echo "[reset] clearing any leftover netem qdisc on client..."
docker exec "$CLIENT" tc qdisc del dev eth1 root netem 2>/dev/null || true

echo "[reset] starting a clean iperf3 server..."
docker exec "$SERVER" pkill -CONT -f "iperf3 -s" 2>/dev/null || true
docker exec "$SERVER" pkill iperf3 2>/dev/null || true
sleep 1
docker exec -d "$SERVER" iperf3 -s

sleep 1
echo "[reset] verifying connectivity..."
if docker exec "$CLIENT" ping -c 2 -W 2 10.0.0.20 >/dev/null 2>&1; then
  echo "[reset] client -> server reachable"
else
  echo "[reset] WARNING: ping failed, check manually"
fi

echo "[reset] done. Run ./check.sh to verify health."
