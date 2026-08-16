#!/usr/bin/env bash
set -uo pipefail

# Lab 26 check - verifies ns1 can actually reach ns2:8080, i.e. the
# ALLOWED chain's rule is actually reachable, not just present.

fail=0

echo "[check] ns2 listener is up"
if ! sudo ip netns exec ns2 pgrep -f "nc -lk 8080" >/dev/null 2>&1; then
  echo "[FAIL] no listener on ns2:8080 - run setup.sh first"
  exit 1
fi

echo "[check] ns1 -> ns2:8080 (should succeed if the allow-list rule is actually reachable)"
if sudo ip netns exec ns1 bash -c 'echo healthcheck | timeout 3 nc -w2 10.10.0.2 8080' >/dev/null 2>&1; then
  echo "[PASS] ns1 reached ns2:8080"
else
  echo "[FAIL] ns1 could not reach ns2:8080 - the allow-list rule isn't taking effect"
  fail=1
fi

echo "[check] ALLOWED chain has actually been hit (packet counter > 0)"
COUNT=$(sudo ip netns exec ns2 iptables -L ALLOWED -n -v 2>/dev/null | awk 'NR==3 {print $1}')
echo "      ALLOWED chain packet count: ${COUNT:-0}"
if [ -z "$COUNT" ] || [ "$COUNT" -eq 0 ]; then
  echo "[FAIL] ALLOWED chain has never been reached."
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[PASS] rule ordering is fixed - the allow-list is actually reachable."
  exit 0
else
  echo "[FAIL] see details above."
  exit 1
fi
