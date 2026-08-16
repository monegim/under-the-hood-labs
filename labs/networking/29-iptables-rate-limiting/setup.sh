#!/usr/bin/env bash
set -euo pipefail

# Lab 29 setup: a bridge with three namespaces - ns1 (noisy client),
# ns2 (server), ns3 (a second, well-behaved client) - so the
# "global rate limit gets exhausted by ONE noisy source and locks out
# everyone else too" lesson is concretely demonstrable, not just
# described. ns2 starts with NO rate limiting at all - a flood from
# ns1 succeeds completely unthrottled.

for ns in ns1 ns2 ns3; do
  sudo ip netns del "$ns" 2>/dev/null || true
done
sudo ip link del br29 2>/dev/null || true

sudo ip link add br29 type bridge
sudo ip link set br29 up

sudo ip netns add ns1
sudo ip netns add ns2
sudo ip netns add ns3

for i in 1 2 3; do
  sudo ip link add veth$i type veth peer name veth$i-br
  sudo ip link set veth$i netns ns$i
  sudo ip link set veth$i-br master br29
  sudo ip link set veth$i-br up
done

sudo ip netns exec ns1 ip addr add 10.30.0.1/24 dev veth1
sudo ip netns exec ns1 ip link set veth1 up
sudo ip netns exec ns1 ip link set lo up

sudo ip netns exec ns2 ip addr add 10.30.0.2/24 dev veth2
sudo ip netns exec ns2 ip link set veth2 up
sudo ip netns exec ns2 ip link set lo up

sudo ip netns exec ns3 ip addr add 10.30.0.3/24 dev veth3
sudo ip netns exec ns3 ip link set veth3 up
sudo ip netns exec ns3 ip link set lo up

echo "[setup] starting a listener on ns2:7000 (accepts one line per connection, then closes)..."
sudo ip netns exec ns2 pkill -f "nc.*7000" 2>/dev/null || true
sleep 1
sudo ip netns exec ns2 bash -c '
  while true; do
    nc -l 7000 -q0 </dev/null >/dev/null 2>&1
  done &
  echo $! > /tmp/lab29-server.pid
' 2>/dev/null || true
sleep 1

echo "[setup] clearing ns2's INPUT chain — no rate limiting at all yet..."
sudo ip netns exec ns2 iptables -F

echo
echo "Done. ns1=10.30.0.1 (will play the noisy client), ns2=10.30.0.2 (server),"
echo "ns3=10.30.0.3 (a second, well-behaved client) — all on br29."
echo
echo "Try flooding it right now (unprotected):"
echo "  sudo ip netns exec ns1 bash -c 'for i in \$(seq 1 20); do echo hi | nc -w1 10.30.0.2 7000; done'"
