#!/usr/bin/env bash
set -uo pipefail

# Lab 5 - Firewalls: destroy and redeploy the containerlab topology, then
# re-apply addressing, ip_forward, the default-DROP FORWARD/INPUT
# policies, and the ACCEPT rules from the README's build steps (Steps
# 1-6) - none of this is baked into the topology file, it's all applied
# live via docker exec.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] destroying existing topology (if any)..."
sudo clab destroy -t "$DIR/topology.clab.yml" --cleanup

echo "[reset] deploying topology fresh..."
sudo clab deploy -t "$DIR/topology.clab.yml"

echo "[reset] addressing everything..."
docker exec clab-firewalls-client ip addr add 10.10.1.10/24 dev eth1
docker exec clab-firewalls-client ip link set eth1 up
docker exec clab-firewalls-client ip route add default via 10.10.1.1

docker exec clab-firewalls-fw ip addr add 10.10.1.1/24 dev eth1
docker exec clab-firewalls-fw ip link set eth1 up
docker exec clab-firewalls-fw ip addr add 10.10.2.1/24 dev eth2
docker exec clab-firewalls-fw ip link set eth2 up
docker exec clab-firewalls-fw sysctl -w net.ipv4.ip_forward=1

docker exec clab-firewalls-server ip addr add 10.10.2.10/24 dev eth1
docker exec clab-firewalls-server ip link set eth1 up
docker exec clab-firewalls-server ip route add default via 10.10.2.1

echo "[reset] starting listener on server:80..."
docker exec -d clab-firewalls-server nc -lp 80

echo "[reset] locking down FORWARD with default-DROP..."
docker exec clab-firewalls-fw iptables -P FORWARD DROP

echo "[reset] adding back allowed FORWARD traffic..."
docker exec clab-firewalls-fw iptables -A FORWARD -i eth1 -o eth2 -p icmp --icmp-type echo-request -j ACCEPT
docker exec clab-firewalls-fw iptables -A FORWARD -i eth1 -o eth2 -p tcp --dport 80 -j ACCEPT
docker exec clab-firewalls-fw iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

echo "[reset] protecting the firewall host itself (INPUT chain)..."
docker exec clab-firewalls-fw iptables -A INPUT -i lo -j ACCEPT
docker exec clab-firewalls-fw iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
docker exec clab-firewalls-fw iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
docker exec clab-firewalls-fw iptables -P INPUT DROP

echo "[reset] Lab 5 topology redeployed and configured fresh"
