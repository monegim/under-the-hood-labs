#!/usr/bin/env bash
set -euo pipefail

# Lab 8 setup: build br0 with ns1/ns2 attached via veth pairs.
# Safe to re-run - tears down any previous state first.

for ns in ns1 ns2; do
  sudo ip netns del "$ns" 2>/dev/null || true
done
sudo ip link del br0 2>/dev/null || true

sudo ip link add name br0 type bridge
sudo ip link set br0 up

sudo ip netns add ns1
sudo ip netns add ns2

sudo ip link add veth1 type veth peer name veth1-br
sudo ip link add veth2 type veth peer name veth2-br

sudo ip link set veth1 netns ns1
sudo ip link set veth2 netns ns2

sudo ip link set veth1-br master br0
sudo ip link set veth2-br master br0
sudo ip link set veth1-br up
sudo ip link set veth2-br up

sudo ip netns exec ns1 ip addr add 10.0.0.1/24 dev veth1
sudo ip netns exec ns1 ip link set veth1 up
sudo ip netns exec ns1 ip link set lo up

sudo ip netns exec ns2 ip addr add 10.0.0.2/24 dev veth2
sudo ip netns exec ns2 ip link set veth2 up
sudo ip netns exec ns2 ip link set lo up

echo "br0 + ns1 + ns2 ready. Test with: sudo ip netns exec ns1 ping -c 3 10.0.0.2"
