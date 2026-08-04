#!/usr/bin/env bash
set -euo pipefail

# Lab 21 setup: two bridges (sw1, sw2) connected by TWO parallel veth links
# (a physical loop) plus h1/h2 hosts. STP is left OFF on both bridges, on
# purpose - this is the "someone plugged in a redundant uplink and never
# turned Spanning Tree on" starting state the lab's README walks you
# through fixing. Safe to re-run - tears down any previous state first.

for ns in h1 h2; do
  sudo ip netns del "$ns" 2>/dev/null || true
done
for br in sw1 sw2; do
  sudo ip link del "$br" 2>/dev/null || true
done

sudo ip link add name sw1 type bridge stp_state 0
sudo ip link add name sw2 type bridge stp_state 0
sudo ip link set sw1 up
sudo ip link set sw2 up

sudo ip netns add h1
sudo ip netns add h2

# host uplinks
sudo ip link add veth-h1 type veth peer name veth-h1-sw1
sudo ip link add veth-h2 type veth peer name veth-h2-sw2
sudo ip link set veth-h1 netns h1
sudo ip link set veth-h2 netns h2
sudo ip link set veth-h1-sw1 master sw1
sudo ip link set veth-h2-sw2 master sw2
sudo ip link set veth-h1-sw1 up
sudo ip link set veth-h2-sw2 up

# two parallel inter-switch links - this is the physical loop
sudo ip link add sw1-a type veth peer name sw2-a
sudo ip link add sw1-b type veth peer name sw2-b
sudo ip link set sw1-a master sw1
sudo ip link set sw2-a master sw2
sudo ip link set sw1-b master sw1
sudo ip link set sw2-b master sw2
sudo ip link set sw1-a up
sudo ip link set sw2-a up
sudo ip link set sw1-b up
sudo ip link set sw2-b up

sudo ip netns exec h1 ip addr add 10.0.0.1/24 dev veth-h1
sudo ip netns exec h1 ip link set veth-h1 up
sudo ip netns exec h1 ip link set lo up

sudo ip netns exec h2 ip addr add 10.0.0.2/24 dev veth-h2
sudo ip netns exec h2 ip link set veth-h2 up
sudo ip netns exec h2 ip link set lo up

echo "sw1/sw2 wired with a redundant double-link loop between them. STP is OFF on both."
echo "See README.md Step 4 onward - do not flood broadcast traffic before reading the safety note."
