#!/usr/bin/env bash
set -euo pipefail

# Lab 26 setup: ns1 (client) <-veth-> ns2 (server), server listens on
# TCP 8080. A custom chain ALLOWED holds the intended allow-list rule,
# but INPUT's own rule order means it never gets reached - a catch-all
# DROP sits before the jump to it. Safe to re-run - tears down first.

for ns in ns1 ns2; do
  sudo ip netns del "$ns" 2>/dev/null || true
done

sudo ip netns add ns1
sudo ip netns add ns2

sudo ip link add veth1 type veth peer name veth2
sudo ip link set veth1 netns ns1
sudo ip link set veth2 netns ns2

sudo ip netns exec ns1 ip addr add 10.10.0.1/24 dev veth1
sudo ip netns exec ns1 ip link set veth1 up
sudo ip netns exec ns1 ip link set lo up

sudo ip netns exec ns2 ip addr add 10.10.0.2/24 dev veth2
sudo ip netns exec ns2 ip link set veth2 up
sudo ip netns exec ns2 ip link set lo up

echo "[setup] starting a listener on ns2:8080..."
sudo ip netns exec ns2 pkill -f "nc -lk 8080" 2>/dev/null || true
sleep 1
sudo ip netns exec ns2 bash -c 'nohup nc -lk 8080 </dev/null >/dev/null 2>&1 &'
sleep 1

echo "[setup] building the broken ruleset inside ns2..."
sudo ip netns exec ns2 iptables -F
sudo ip netns exec ns2 iptables -X ALLOWED 2>/dev/null || true

# The custom chain itself is correct...
sudo ip netns exec ns2 iptables -N ALLOWED
sudo ip netns exec ns2 iptables -A ALLOWED -s 10.10.0.1 -j ACCEPT

# ...but INPUT's rule order buries the jump to it after a catch-all DROP.
sudo ip netns exec ns2 iptables -A INPUT -i lo -j ACCEPT
sudo ip netns exec ns2 iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec ns2 iptables -A INPUT -j DROP
sudo ip netns exec ns2 iptables -A INPUT -p tcp --dport 8080 -j ALLOWED

echo
echo "[setup] done. ns2's INPUT chain (note the order):"
sudo ip netns exec ns2 iptables -L INPUT -n -v --line-numbers
echo
echo "Try: sudo ip netns exec ns1 bash -c 'echo hi | nc -w2 10.10.0.2 8080'"
