#!/usr/bin/env bash
# Lab 16 (Asymmetric Routing) — destroys and redeploys the topology, then
# re-applies the README's Steps 1-6 live config: builds the two bridge
# nodes, addresses everyone, sets up symmetric routing via r1, configures
# r2's stateful firewall (present but inactive while routing stays
# symmetric), and starts the HTTP listener. None of this is baked into
# the topology file.
set -uo pipefail

LAB="asym-routing"
CLIENT="clab-${LAB}-client"
SWA="clab-${LAB}-switch-a"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
SWB="clab-${LAB}-switch-b"
SERVER="clab-${LAB}-server"

cd "$(dirname "$0")"

echo "[reset] destroying existing topology (if any)..."
sudo containerlab destroy -t topology.clab.yml --cleanup

echo "[reset] deploying topology..."
sudo containerlab deploy -t topology.clab.yml

echo "[reset] waiting for nodes to be ready..."
for c in "$CLIENT" "$SWA" "$R1" "$R2" "$SWB" "$SERVER"; do
  ready=0
  for i in $(seq 1 30); do
    docker exec "$c" true >/dev/null 2>&1 && { ready=1; break; }
    sleep 2
  done
  [ "$ready" -eq 1 ] || { echo "[reset] ERROR: $c never became ready"; exit 1; }
done

echo "[reset] installing tools (this can take a minute)..."
for n in "$CLIENT" "$SWA" "$R1" "$R2" "$SWB" "$SERVER"; do
  docker exec "$n" bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump iptables conntrack python3 curl procps >/dev/null"
done

echo "[reset] building bridge on switch-a..."
docker exec "$SWA" bash -c "
  ip link add name br0 type bridge
  ip link set br0 up
  ip link set eth1 master br0
  ip link set eth2 master br0
  ip link set eth3 master br0
  ip link set eth1 up
  ip link set eth2 up
  ip link set eth3 up
"

echo "[reset] building bridge on switch-b..."
docker exec "$SWB" bash -c "
  ip link add name br0 type bridge
  ip link set br0 up
  ip link set eth1 master br0
  ip link set eth2 master br0
  ip link set eth3 master br0
  ip link set eth1 up
  ip link set eth2 up
  ip link set eth3 up
"

echo "[reset] addressing client/r1/r2/server..."
docker exec "$CLIENT" ip addr add 10.0.1.10/24 dev eth1
docker exec "$CLIENT" ip link set eth1 up

docker exec "$R1" ip addr add 10.0.1.1/24 dev eth1
docker exec "$R1" ip link set eth1 up
docker exec "$R1" ip addr add 10.0.2.1/24 dev eth2
docker exec "$R1" ip link set eth2 up
docker exec "$R1" sysctl -w net.ipv4.ip_forward=1

docker exec "$R2" ip addr add 10.0.1.2/24 dev eth1
docker exec "$R2" ip link set eth1 up
docker exec "$R2" ip addr add 10.0.2.2/24 dev eth2
docker exec "$R2" ip link set eth2 up
docker exec "$R2" sysctl -w net.ipv4.ip_forward=1

docker exec "$SERVER" ip addr add 10.0.2.10/24 dev eth1
docker exec "$SERVER" ip link set eth1 up

echo "[reset] setting up symmetric routing via r1..."
docker exec "$CLIENT" ip route replace 10.0.2.0/24 via 10.0.1.1 dev eth1
docker exec "$SERVER" ip route replace 10.0.1.0/24 via 10.0.2.1 dev eth1

echo "[reset] resetting r1's firewall to permissive..."
docker exec "$R1" iptables -P FORWARD ACCEPT
docker exec "$R1" iptables -F FORWARD

echo "[reset] configuring r2's stateful firewall (present but inactive while routing is symmetric)..."
docker exec "$R2" iptables -P FORWARD ACCEPT
docker exec "$R2" iptables -F FORWARD
docker exec "$R2" iptables -P FORWARD DROP
docker exec "$R2" iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
docker exec "$R2" iptables -A FORWARD -p icmp -j ACCEPT
docker exec "$R2" sysctl -w net.netfilter.nf_conntrack_tcp_loose=0

echo "[reset] starting the HTTP listener on the server..."
docker exec -d "$SERVER" python3 -m http.server 8080 --bind 0.0.0.0
sleep 1

echo "[reset] verifying end-to-end connectivity..."
if docker exec "$CLIENT" curl -s --max-time 5 http://10.0.2.10:8080/ -o /dev/null; then
  echo "[reset] client -> server:8080 reachable"
else
  echo "[reset] WARNING: curl failed, check manually"
fi

echo "[reset] done. Run ./check.sh to verify health."
