#!/usr/bin/env bash
set -euo pipefail

# Lab 22 setup: two namespaces (h1, h2), each with a bond0 in 802.3ad mode
# aggregating two veth links between them. LACP negotiates peer-to-peer,
# so no switch is needed - h1 and h2's bonding drivers talk LACP directly
# to each other over veth-h1a<->veth-h2a and veth-h1b<->veth-h2b.
# Safe to re-run - tears down any previous state first.

sudo modprobe bonding max_bonds=0 2>/dev/null || true

for ns in h1 h2 h3; do
  sudo ip netns del "$ns" 2>/dev/null || true
done

sudo ip netns add h1
sudo ip netns add h2

sudo ip link add veth-h1a type veth peer name veth-h2a
sudo ip link add veth-h1b type veth peer name veth-h2b

sudo ip link set veth-h1a netns h1
sudo ip link set veth-h1b netns h1
sudo ip link set veth-h2a netns h2
sudo ip link set veth-h2b netns h2

sudo ip netns exec h1 ip link add bond0 type bond mode 802.3ad miimon 100 lacp_rate fast
sudo ip netns exec h2 ip link add bond0 type bond mode 802.3ad miimon 100 lacp_rate fast

sudo ip netns exec h1 ip link set veth-h1a master bond0
sudo ip netns exec h1 ip link set veth-h1b master bond0
sudo ip netns exec h2 ip link set veth-h2a master bond0
sudo ip netns exec h2 ip link set veth-h2b master bond0

sudo ip netns exec h1 ip link set veth-h1a up
sudo ip netns exec h1 ip link set veth-h1b up
sudo ip netns exec h2 ip link set veth-h2a up
sudo ip netns exec h2 ip link set veth-h2b up

sudo ip netns exec h1 ip addr add 10.10.10.1/24 dev bond0
sudo ip netns exec h2 ip addr add 10.10.10.2/24 dev bond0

sudo ip netns exec h1 ip link set bond0 up
sudo ip netns exec h2 ip link set bond0 up
sudo ip netns exec h1 ip link set lo up
sudo ip netns exec h2 ip link set lo up

echo "waiting for LACP to negotiate (lacp_rate fast, should take a couple seconds)..."
sleep 3

echo "h1 (10.10.10.1) <-> h2 (10.10.10.2) bonded via 2-link 802.3ad aggregate."
echo "Test with: sudo ip netns exec h1 ping -c 3 10.10.10.2"
echo "Inspect with: sudo ip netns exec h1 cat /proc/net/bonding/bond0"
