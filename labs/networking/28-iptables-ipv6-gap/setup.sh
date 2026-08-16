#!/usr/bin/env bash
set -euo pipefail

# Lab 28 setup: ns1 (client) <-veth-> ns2 (server), both addressed for
# IPv4 AND IPv6 (a ULA prefix, fd00:26::/64). A dual-stack listener
# runs on ns2:9090. iptables (v4) locks the port down correctly;
# ip6tables is never touched — completely default-open, no rules at
# all. Safe to re-run — tears down first.

for ns in ns1 ns2; do
  sudo ip netns del "$ns" 2>/dev/null || true
done

sudo ip netns add ns1
sudo ip netns add ns2

sudo ip link add veth1 type veth peer name veth2
sudo ip link set veth1 netns ns1
sudo ip link set veth2 netns ns2

sudo ip netns exec ns1 ip addr add 10.20.0.1/24 dev veth1
sudo ip netns exec ns1 ip -6 addr add fd00:26::1/64 dev veth1
sudo ip netns exec ns1 ip link set veth1 up
sudo ip netns exec ns1 ip link set lo up

sudo ip netns exec ns2 ip addr add 10.20.0.2/24 dev veth2
sudo ip netns exec ns2 ip -6 addr add fd00:26::2/64 dev veth2
sudo ip netns exec ns2 ip link set veth2 up
sudo ip netns exec ns2 ip link set lo up

sleep 1   # let DAD (duplicate address detection) settle on the v6 addresses

echo "[setup] starting a dual-stack listener on ns2:9090..."
sudo ip netns exec ns2 pkill -f "nc.*9090" 2>/dev/null || true
sleep 1
# Two separate nc listeners (v4 and v6) — most 'nc' builds don't do a
# single dual-stack bind the way a real app's socket(AF_INET6, ...,
# with IPV6_V6ONLY=0) would; this is the same outcome from the
# perspective of "the service is reachable over both stacks", which is
# what matters for this lab.
sudo ip netns exec ns2 bash -c 'nohup nc -lk 9090 </dev/null >/dev/null 2>&1 &'
sudo ip netns exec ns2 bash -c 'nohup nc -6 -lk 9090 </dev/null >/dev/null 2>&1 &'
sleep 1

echo "[setup] locking the port down over IPv4 only, inside ns2..."
sudo ip netns exec ns2 iptables -F
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 9090 -j DROP

echo "[setup] ip6tables inside ns2 is left completely untouched (default ACCEPT, no rules)."
sudo ip netns exec ns2 ip6tables -F 2>/dev/null || true

echo
echo "Done."
echo "IPv4 rule:"
sudo ip netns exec ns2 iptables -L INPUT -n
echo
echo "IPv6 rules (note: empty):"
sudo ip netns exec ns2 ip6tables -L INPUT -n
