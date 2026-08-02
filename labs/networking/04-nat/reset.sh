#!/usr/bin/env bash
set -uo pipefail

# Lab 4 - NAT: destroy and redeploy the containerlab topology, then
# re-apply addressing, ip_forward, MASQUERADE, and DNAT from the README's
# build steps (Steps 2, 3, 5, 6) - none of this is baked into the
# topology file, it's all applied live via docker exec.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] destroying existing topology (if any)..."
sudo clab destroy -t "$DIR/topology.clab.yml" --cleanup

echo "[reset] deploying topology fresh..."
sudo clab deploy -t "$DIR/topology.clab.yml"

echo "[reset] addressing everything..."
docker exec clab-nat-host-int ip addr add 192.168.100.10/24 dev eth1
docker exec clab-nat-host-int ip link set eth1 up
docker exec clab-nat-host-int ip route add default via 192.168.100.1

docker exec clab-nat-router ip addr add 192.168.100.1/24 dev eth1
docker exec clab-nat-router ip link set eth1 up
docker exec clab-nat-router ip addr add 203.0.113.1/24 dev eth2
docker exec clab-nat-router ip link set eth2 up

docker exec clab-nat-host-ext ip addr add 203.0.113.10/24 dev eth1
docker exec clab-nat-host-ext ip link set eth1 up

echo "[reset] enabling ip_forward on router..."
docker exec clab-nat-router sysctl -w net.ipv4.ip_forward=1

echo "[reset] adding MASQUERADE for outbound traffic..."
docker exec clab-nat-router iptables -t nat -A POSTROUTING -o eth2 -s 192.168.100.0/24 -j MASQUERADE

echo "[reset] adding DNAT for inbound port 8080..."
docker exec clab-nat-router iptables -t nat -A PREROUTING -i eth2 -p tcp --dport 8080 -j DNAT --to-destination 192.168.100.10:8080
docker exec clab-nat-router iptables -A FORWARD -p tcp -d 192.168.100.10 --dport 8080 -j ACCEPT

echo "[reset] starting listener on host-int:8080..."
docker exec -d clab-nat-host-int nc -lp 8080

echo "[reset] Lab 4 topology redeployed and configured fresh"
