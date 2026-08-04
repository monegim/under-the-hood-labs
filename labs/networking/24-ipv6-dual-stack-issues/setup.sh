#!/usr/bin/env bash
set -euo pipefail

# Lab 24 setup: client/server namespaces on one veth link, dual-stacked
# with both IPv4 and IPv6 addresses. Server runs two independent
# python3 http.server processes, one bound to each address family on
# port 80. Nothing is broken yet - see README.md Step 3 onward.
# Safe to re-run - tears down any previous state first.

for ns in client server; do
  sudo ip netns del "$ns" 2>/dev/null || true
done
sudo pkill -f "http.server 80" 2>/dev/null || true

sudo ip netns add client
sudo ip netns add server

sudo ip link add veth-client type veth peer name veth-server
sudo ip link set veth-client netns client
sudo ip link set veth-server netns server

sudo ip netns exec client ip addr add 10.0.0.1/24 dev veth-client
sudo ip netns exec client ip addr add fd00::1/64 dev veth-client
sudo ip netns exec client ip link set veth-client up
sudo ip netns exec client ip link set lo up

sudo ip netns exec server ip addr add 10.0.0.2/24 dev veth-server
sudo ip netns exec server ip addr add fd00::2/64 dev veth-server
sudo ip netns exec server ip link set veth-server up
sudo ip netns exec server ip link set lo up

echo "waiting for IPv6 DAD to finish..."
sleep 2

echo "starting HTTP listeners on server (one per address family, port 80)..."
sudo ip netns exec server bash -c 'setsid python3 -m http.server 80 --bind 10.0.0.2 >/tmp/lab24-http4.log 2>&1 < /dev/null &'
sudo ip netns exec server bash -c 'setsid python3 -m http.server 80 --bind fd00::2 >/tmp/lab24-http6.log 2>&1 < /dev/null &'
sleep 1

echo "client: 10.0.0.1 / fd00::1   server: 10.0.0.2 / fd00::2 (port 80, both stacks)"
echo "Test with:"
echo "  sudo ip netns exec client ping -c 2 10.0.0.2"
echo "  sudo ip netns exec client ping6 -c 2 fd00::2"
echo "  sudo ip netns exec client curl -4 http://10.0.0.2/"
echo "  sudo ip netns exec client curl -6 http://[fd00::2]/"
