#!/usr/bin/env bash
set -uo pipefail

# Lab 33 check - verifies client can actually reach upstream through
# router's NAT right now.

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] upstream listener is up"
if ! sudo ip netns exec upstream pgrep -f lab33-upstream.py >/dev/null 2>&1; then
  fail "no listener on upstream:9200 - run setup.sh first"
fi

echo "[check] client -> upstream through router's NAT"
OUT=$(sudo ip netns exec client bash -c 'echo healthcheck | timeout 3 nc -w3 192.0.2.20 9200' 2>/dev/null || true)
echo "      response: ${OUT:-<none>}"
if [ "$OUT" = "UPSTREAM-OK" ]; then
  echo "[PASS] client reached upstream - NAT is using a valid, currently-owned source address."
  exit 0
else
  fail "client could not reach upstream - NAT is rewriting to an address router no longer has."
fi
