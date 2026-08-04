#!/usr/bin/env bash
# Lab 24 (IPv6 Dual-Stack Issues) - verifies both address families are
# genuinely healthy end to end: ping and an actual HTTP request over
# both IPv4 and IPv6, not just address presence.
set -uo pipefail

fail=0

echo "[check] client/server namespaces exist"
for ns in client server; do
  if ! sudo ip netns list | grep -q "^${ns}\b"; then
    echo "[FAIL] namespace $ns does not exist - run setup.sh first"
    exit 1
  fi
done

echo "[check] IPv4 reachability (ping)"
if sudo ip netns exec client ping -c 2 -W 2 10.0.0.2 >/dev/null 2>&1; then
  echo "[PASS] IPv4 ping ok"
else
  echo "[FAIL] IPv4 ping failed"
  fail=1
fi

echo "[check] IPv6 reachability (ping6)"
if sudo ip netns exec client ping6 -c 2 -W 2 fd00::2 >/dev/null 2>&1; then
  echo "[PASS] IPv6 ping6 ok"
else
  echo "[FAIL] IPv6 ping6 failed - check for a Neighbor Discovery block (Challenge A)"
  fail=1
fi

echo "[check] IPv4 HTTP service reachability"
if sudo ip netns exec client curl -4 --max-time 3 -s -o /dev/null http://10.0.0.2/ 2>/dev/null; then
  echo "[PASS] curl -4 ok"
else
  echo "[FAIL] curl -4 failed"
  fail=1
fi

echo "[check] IPv6 HTTP service reachability"
if sudo ip netns exec client curl -6 --max-time 3 -s -o /dev/null http://[fd00::2]/ 2>/dev/null; then
  echo "[PASS] curl -6 ok"
else
  echo "[FAIL] curl -6 failed - IPv6 service port may still be blackholed (README Step 3 / Step 7 fix)"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[PASS] Lab 24 topology is healthy"
  exit 0
else
  echo "[FAIL] Lab 24 topology has issues (see above)"
  exit 1
fi
