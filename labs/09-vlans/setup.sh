#!/usr/bin/env bash
set -euo pipefail

# Lab 9 setup: VLAN-aware bridge with ns1/ns2 on VLAN 10, ns3/ns4 on VLAN 20,
# plus a router namespace trunked into both. Safe to re-run - tears down any
# previous state first.

for ns in ns1 ns2 ns3 ns4 router; do
  sudo ip netns del "$ns" 2>/dev/null || true
done
sudo ip link del br0 2>/dev/null || true

sudo modprobe 8021q

sudo ip link add name br0 type bridge vlan_filtering 1
sudo ip link set br0 up

for ns in ns1 ns2 ns3 ns4; do
  sudo ip netns add "$ns"
done

for n in 1 2 3 4; do
  sudo ip link add veth$n type veth peer name veth$n-br
  sudo ip link set veth$n netns ns$n
  sudo ip link set veth$n-br master br0
  sudo ip link set veth$n-br up
  sudo ip netns exec ns$n ip link set veth$n up
  sudo ip netns exec ns$n ip link set lo up
done

sudo ip netns exec ns1 ip addr add 10.10.0.1/24 dev veth1
sudo ip netns exec ns2 ip addr add 10.10.0.2/24 dev veth2
sudo ip netns exec ns3 ip addr add 10.20.0.1/24 dev veth3
sudo ip netns exec ns4 ip addr add 10.20.0.2/24 dev veth4

for n in 1 2; do
  sudo bridge vlan del dev veth$n-br vid 1
  sudo bridge vlan add dev veth$n-br vid 10 pvid untagged
done
for n in 3 4; do
  sudo bridge vlan del dev veth$n-br vid 1
  sudo bridge vlan add dev veth$n-br vid 20 pvid untagged
done

sudo ip netns add router
sudo ip link add veth5 type veth peer name veth5-br
sudo ip link set veth5 netns router
sudo ip link set veth5-br master br0
sudo ip link set veth5-br up
sudo ip netns exec router ip link set veth5 up
sudo ip netns exec router ip link set lo up

sudo bridge vlan del dev veth5-br vid 1
sudo bridge vlan add dev veth5-br vid 10
sudo bridge vlan add dev veth5-br vid 20

sudo ip netns exec router ip link add link veth5 name veth5.10 type vlan id 10
sudo ip netns exec router ip link add link veth5 name veth5.20 type vlan id 20
sudo ip netns exec router ip addr add 10.10.0.254/24 dev veth5.10
sudo ip netns exec router ip addr add 10.20.0.254/24 dev veth5.20
sudo ip netns exec router ip link set veth5.10 up
sudo ip netns exec router ip link set veth5.20 up

echo "br0 (VLAN 10: ns1,ns2 / VLAN 20: ns3,ns4) + router trunk ready."
echo "Test same-VLAN:  sudo ip netns exec ns1 ping -c 2 10.10.0.2"
echo "Test isolation:  sudo ip netns exec ns1 ping -c 2 10.20.0.1"
echo "Test trunk:      sudo ip netns exec router ping -c 2 10.20.0.1"
