#!/usr/bin/env bash
set -euo pipefail

# Lab 33 setup: client -> router -> upstream. router NATs client's
# traffic using static SNAT hardcoded to its *current* external
# address. Then router's external address changes (a DHCP renewal, a
# failover, an ISP reassignment) - the SNAT rule keeps rewriting to
# the now-stale, no-longer-owned address. upstream's ARP cache still
# maps that stale address to router's MAC for a while (this is the
# realistic part: the breakage doesn't show up the instant the IP
# changes) - setup.sh flushes it to simulate that cache naturally
# expiring, so the incident reproduces immediately instead of "wait an
# indeterminate amount of time." Safe to re-run - tears down first.

for ns in client router upstream; do
  sudo ip netns del "$ns" 2>/dev/null || true
done

sudo ip netns add client
sudo ip netns add router
sudo ip netns add upstream

# client <-> router (internal side)
sudo ip link add veth-c type veth peer name veth-r-in
sudo ip link set veth-c netns client
sudo ip link set veth-r-in netns router
sudo ip netns exec client ip addr add 10.60.0.2/24 dev veth-c
sudo ip netns exec client ip link set veth-c up
sudo ip netns exec client ip link set lo up
sudo ip netns exec router ip addr add 10.60.0.1/24 dev veth-r-in
sudo ip netns exec router ip link set veth-r-in up

# router <-> upstream (external side) - router's "public" address
sudo ip link add veth-r-ext type veth peer name veth-u
sudo ip link set veth-r-ext netns router
sudo ip link set veth-u netns upstream
sudo ip netns exec router ip addr add 192.0.2.10/24 dev veth-r-ext
sudo ip netns exec router ip link set veth-r-ext up
sudo ip netns exec upstream ip addr add 192.0.2.20/24 dev veth-u
sudo ip netns exec upstream ip link set veth-u up
sudo ip netns exec upstream ip link set lo up
sudo ip netns exec router ip link set lo up

sudo ip netns exec client ip route add default via 10.60.0.1 dev veth-c
sudo ip netns exec router sysctl -w net.ipv4.ip_forward=1 >/dev/null

echo "[setup] configuring static SNAT, hardcoded to router's current address (192.0.2.10)..."
sudo ip netns exec router iptables -t nat -F
sudo ip netns exec router iptables -t nat -A POSTROUTING -o veth-r-ext -j SNAT --to-source 192.0.2.10

echo "[setup] starting the upstream service..."
sudo ip netns exec upstream pkill -f lab33-upstream 2>/dev/null || true
sleep 1
cat > /tmp/lab33-upstream.py <<'EOF'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", 9200))
s.listen(5)
while True:
    conn, _ = s.accept()
    conn.sendall(b"UPSTREAM-OK\n")
    conn.close()
EOF
sudo ip netns exec upstream python3 /tmp/lab33-upstream.py >/tmp/lab33-upstream.log 2>&1 &
disown 2>/dev/null || true
sleep 1

echo "[setup] confirming the baseline works..."
sudo ip netns exec client bash -c 'echo baseline | nc -w3 192.0.2.20 9200'

echo "[setup] INJECTING THE FAULT: router's external address 'renews' to a new one..."
sudo ip netns exec router ip addr del 192.0.2.10/24 dev veth-r-ext
sudo ip netns exec router ip addr add 192.0.2.15/24 dev veth-r-ext

echo "[setup] simulating upstream's ARP cache for the old address naturally expiring..."
sudo ip netns exec upstream ip neigh flush all

echo
echo "Done. router's SNAT rule still rewrites to 192.0.2.10 - which router no longer has."
echo "Try:"
echo "  sudo ip netns exec client bash -c 'echo hi | nc -w3 192.0.2.20 9200'"
