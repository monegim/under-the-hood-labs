#!/usr/bin/env bash
# Lab 22 (LACP Bonding Failure) - verifies both h1 and h2 have a healthy
# 2-port 802.3ad aggregate (not just 2 up links) and can reach each other.
set -uo pipefail

fail=0

echo "[check] h1/h2 namespaces exist"
for ns in h1 h2; do
  if ! sudo ip netns list | grep -q "^${ns}\b"; then
    echo "[FAIL] namespace $ns does not exist - run setup.sh first"
    exit 1
  fi
done

echo "[check] bond0 exists in both namespaces"
for ns in h1 h2; do
  if ! sudo ip netns exec "$ns" ip link show bond0 >/dev/null 2>&1; then
    echo "[FAIL] bond0 missing in $ns"
    exit 1
  fi
done

echo "[check] active aggregator port count on h1 and h2"
for ns in h1 h2; do
  bonding_info=$(sudo ip netns exec "$ns" cat /proc/net/bonding/bond0 2>/dev/null)
  ports=$(echo "$bonding_info" | grep -A2 "Active Aggregator Info" | grep "Number of ports" | grep -oE '[0-9]+' | head -1)
  if [ "$ports" = "2" ]; then
    echo "[PASS] $ns: active aggregator has 2 ports"
  else
    echo "[FAIL] $ns: active aggregator has '${ports:-unknown}' ports (expected 2)"
    fail=1
  fi
done

echo "[check] h1 -> h2 connectivity (10.10.10.1 -> 10.10.10.2)"
if sudo ip netns exec h1 ping -c 3 -W 2 10.10.10.2 >/dev/null 2>&1; then
  echo "[PASS] h1 can ping h2 across the bond"
else
  echo "[FAIL] h1 cannot ping h2"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[PASS] Lab 22 topology is healthy"
  exit 0
else
  echo "[FAIL] Lab 22 topology has issues (see above)"
  exit 1
fi
