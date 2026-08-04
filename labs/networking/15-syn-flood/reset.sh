#!/usr/bin/env bash
# Lab 15 (SYN Flood) — destroys and redeploys the topology, then re-runs
# the README's Steps 1-6 live config (package install, addressing, a
# fresh listener, and the hardened end state) — none of this is baked
# into the topology file. Leaves the victim in the healthy end-of-Steps
# state (syncookies ON, no flood running) — the two challenges each
# re-disable syncookies deliberately to set up their own scenario.
set -uo pipefail

LAB="syn-flood"
ATTACKER="clab-${LAB}-attacker"
VICTIM="clab-${LAB}-victim"

cd "$(dirname "$0")"

echo "[reset] destroying existing topology (if any)..."
sudo containerlab destroy -t topology.clab.yml --cleanup

echo "[reset] deploying topology..."
sudo containerlab deploy -t topology.clab.yml

echo "[reset] waiting for nodes to be ready..."
for c in "$ATTACKER" "$VICTIM"; do
  ready=0
  for i in $(seq 1 30); do
    docker exec "$c" true >/dev/null 2>&1 && { ready=1; break; }
    sleep 2
  done
  [ "$ready" -eq 1 ] || { echo "[reset] ERROR: $c never became ready"; exit 1; }
done

echo "[reset] installing tools (this can take a minute)..."
docker exec "$ATTACKER" bash -c \
  "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping hping3 netcat-openbsd >/dev/null"
docker exec "$VICTIM" bash -c \
  "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping python3 net-tools procps >/dev/null"

echo "[reset] addressing interfaces..."
docker exec "$ATTACKER" ip addr add 10.0.0.10/24 dev eth1
docker exec "$ATTACKER" ip link set eth1 up

docker exec "$VICTIM" ip addr add 10.0.0.20/24 dev eth1
docker exec "$VICTIM" ip link set eth1 up

echo "[reset] stopping any leftover flood/listener..."
docker exec "$ATTACKER" pkill hping3 2>/dev/null || true
docker exec "$VICTIM" pkill -f "python3" 2>/dev/null || true
sleep 1

echo "[reset] restoring the healthy end-of-Steps state on victim (syncookies ON)..."
docker exec "$VICTIM" sysctl -w net.ipv4.tcp_syncookies=1
docker exec "$VICTIM" sysctl -w net.ipv4.tcp_max_syn_backlog=128

echo "[reset] starting a fresh listener on victim:8080..."
docker exec -d "$VICTIM" python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 8080))
s.listen(128)
while True:
    conn, addr = s.accept()
    conn.close()
"

sleep 1
echo "[reset] verifying baseline connectivity..."
if docker exec "$ATTACKER" nc -zv -w 3 10.0.0.20 8080 >/dev/null 2>&1; then
  echo "[reset] attacker -> victim:8080 reachable"
else
  echo "[reset] WARNING: baseline connect failed, check manually"
fi

echo "[reset] done (victim is hardened — syncookies on, no flood running)."
echo "[reset] Run ./check.sh to verify health."
