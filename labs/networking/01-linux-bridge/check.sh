#!/usr/bin/env bash
set -uo pipefail

# Lab 1 - Linux Bridge: verify br0 is up, veth1-br/veth2-br are enslaved
# and up, and ns1 can ping ns2 across the bridge.

fail=0

echo "[check] br0 link state"
if ! ip -d link show br0 up >/dev/null 2>&1; then
  echo "[FAIL] br0 is missing or administratively DOWN"
  fail=1
else
  echo "[PASS] br0 exists and is UP"
fi

for port in veth1-br veth2-br; do
  echo "[check] $port enslaved to br0 and UP"
  state=$(ip -d link show "$port" 2>/dev/null)
  if [ -z "$state" ]; then
    echo "[FAIL] $port does not exist"
    fail=1
    continue
  fi
  if ! echo "$state" | grep -q "master br0"; then
    echo "[FAIL] $port is not enslaved to br0"
    fail=1
  elif ! echo "$state" | grep -q "state UP"; then
    echo "[FAIL] $port is DOWN"
    fail=1
  else
    echo "[PASS] $port is enslaved to br0 and UP"
  fi
done

echo "[check] ns1 -> ns2 connectivity (10.0.0.1 -> 10.0.0.2)"
if sudo ip netns exec ns1 ping -c 3 -W 2 10.0.0.2 >/dev/null 2>&1; then
  echo "[PASS] ns1 can ping ns2 across br0"
else
  echo "[FAIL] ns1 cannot ping ns2"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[PASS] Lab 1 topology is healthy"
  exit 0
else
  echo "[FAIL] Lab 1 topology has issues (see above)"
  exit 1
fi
