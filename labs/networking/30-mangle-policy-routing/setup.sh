#!/usr/bin/env bash
set -euo pipefail

# Lab 30 setup: client -> router -> {gwa (default path), gwb -> target
# (special path)}. router's main routing table has NO route to
# target's subnet at all - only a custom table 100 does. router's
# mangle PREROUTING chain correctly MARKs client's traffic bound for
# target's service port, but the `ip rule` that would send marked
# traffic to table 100 is missing - so the mark fires and does
# nothing, silently. Safe to re-run - tears down first.

for ns in client router gwa gwb target; do
  sudo ip netns del "$ns" 2>/dev/null || true
done

for ns in client router gwa gwb target; do
  sudo ip netns add "$ns"
done

# client <-> router
sudo ip link add veth-c-r type veth peer name veth-r-c
sudo ip link set veth-c-r netns client
sudo ip link set veth-r-c netns router
sudo ip netns exec client ip addr add 10.40.0.2/24 dev veth-c-r
sudo ip netns exec client ip link set veth-c-r up
sudo ip netns exec router ip addr add 10.40.0.1/24 dev veth-r-c
sudo ip netns exec router ip link set veth-r-c up

# router <-> gwa (the default/main path - doesn't lead to target)
sudo ip link add veth-r-a type veth peer name veth-a-r
sudo ip link set veth-r-a netns router
sudo ip link set veth-a-r netns gwa
sudo ip netns exec router ip addr add 10.10.0.1/24 dev veth-r-a
sudo ip netns exec router ip link set veth-r-a up
sudo ip netns exec gwa ip addr add 10.10.0.2/24 dev veth-a-r
sudo ip netns exec gwa ip link set veth-a-r up

# router <-> gwb (the special path - the only way to reach target)
sudo ip link add veth-r-b type veth peer name veth-b-r
sudo ip link set veth-r-b netns router
sudo ip link set veth-b-r netns gwb
sudo ip netns exec router ip addr add 10.20.0.1/24 dev veth-r-b
sudo ip netns exec router ip link set veth-r-b up
sudo ip netns exec gwb ip addr add 10.20.0.2/24 dev veth-b-r
sudo ip netns exec gwb ip link set veth-b-r up

# gwb <-> target
sudo ip link add veth-b-t type veth peer name veth-t-b
sudo ip link set veth-b-t netns gwb
sudo ip link set veth-t-b netns target
sudo ip netns exec gwb ip addr add 10.30.0.1/24 dev veth-b-t
sudo ip netns exec gwb ip link set veth-b-t up
sudo ip netns exec target ip addr add 10.30.0.2/24 dev veth-t-b
sudo ip netns exec target ip link set veth-t-b up

for ns in client router gwa gwb target; do
  sudo ip netns exec "$ns" ip link set lo up
done

# routing: client's default is router; target's default is gwb; gwb
# forwards between router and target and knows how to reach client's
# subnet to route replies back.
sudo ip netns exec client ip route add default via 10.40.0.1 dev veth-c-r
sudo ip netns exec target ip route add default via 10.30.0.1 dev veth-t-b
sudo ip netns exec gwb ip route add 10.40.0.0/24 via 10.20.0.1 dev veth-b-r
sudo ip netns exec gwb sysctl -w net.ipv4.ip_forward=1 >/dev/null

# router's own default route only reaches gwa - there is NO route to
# target's subnet (10.30.0.0/24) in the main table at all.
sudo ip netns exec router ip route add default via 10.10.0.2 dev veth-r-a
sudo ip netns exec router sysctl -w net.ipv4.ip_forward=1 >/dev/null

# the route to target DOES exist, but only in custom table 100.
sudo ip netns exec router ip route flush table 100 2>/dev/null || true
sudo ip netns exec router ip route add 10.30.0.0/24 via 10.20.0.2 dev veth-r-b table 100

# router marks client's traffic bound for target's service port -
# this part is correct and does fire.
sudo ip netns exec router iptables -t mangle -F
sudo ip netns exec router iptables -t mangle -A PREROUTING -p tcp --dport 9000 -j MARK --set-mark 0x64

echo "[setup] starting the target service..."
sudo ip netns exec target pkill -f "socketserver" 2>/dev/null || true
sleep 1
sudo ip netns exec target python3 -c '
import socketserver

class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.sendall(b"TARGET-SERVICE-OK\n")

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True

with Server(("0.0.0.0", 9000), Handler) as srv:
    srv.serve_forever()
' >/tmp/lab30-target.log 2>&1 &
disown 2>/dev/null || true
sleep 1

echo
echo "[setup] done. router's mangle PREROUTING chain (note: it fires) and ip rule table (note: table 100 is never consulted):"
sudo ip netns exec router iptables -t mangle -L PREROUTING -n -v
sudo ip netns exec router ip rule show
echo
echo "Try: sudo ip netns exec client bash -c 'echo hi | nc -w3 10.30.0.2 9000'"
