#!/usr/bin/env bash
# Lab 17 (Conntrack Exhaustion) — destroys and redeploys the topology,
# then re-applies the README's Steps 1-3 live config (package install,
# addressing, forwarding, the small conntrack table, and the listener) —
# none of this is baked into the topology file. Also makes sure no
# leftover background connections from a previous challenge run are still
# holding the table full.
set -uo pipefail

LAB="conntrack-lab"
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
for n in "$CLIENT" "$R1" "$SERVER"; do
  docker exec "$n" bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping iptables conntrack python3 procps >/dev/null"
done

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

echo "[reset] configuring conntrack tracking and table size on r1..."
docker exec "$R1" iptables -F FORWARD
docker exec "$R1" iptables -A FORWARD -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
docker exec "$R1" sysctl -w net.netfilter.nf_conntrack_max=128
docker exec "$R1" conntrack -F 2>/dev/null || true

echo "[reset] killing any leftover client-side background connections..."
docker exec "$CLIENT" pkill -f "dev/tcp" 2>/dev/null || true
docker exec "$SERVER" pkill -f "python3" 2>/dev/null || true
sleep 1

echo "[reset] starting a fresh listener on server:9090..."
docker exec -d "$SERVER" python3 -c "
import socket, threading
def handle(c):
    try:
        c.recv(1)
    except Exception:
        pass
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 9090))
s.listen(1024)
while True:
    conn, addr = s.accept()
    threading.Thread(target=handle, args=(conn,), daemon=True).start()
"

sleep 1
echo "[reset] verifying baseline connectivity..."
if docker exec "$CLIENT" bash -c 'timeout 5 bash -c "exec 3<>/dev/tcp/10.0.2.10/9090 && echo ok"' >/dev/null 2>&1; then
  echo "[reset] client -> server:9090 reachable"
else
  echo "[reset] WARNING: baseline connect failed, check manually"
fi

echo "[reset] done. Run ./check.sh to verify health."
