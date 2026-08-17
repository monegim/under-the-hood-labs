#!/usr/bin/env bash
set -uo pipefail

# Lab 30 check - verifies client can actually reach target's service,
# i.e. marked traffic is genuinely being policy-routed via table 100,
# not just marked.

fail=0

echo "[check] target listener is up"
if ! sudo ip netns exec target pgrep -f "socketserver" >/dev/null 2>&1; then
  echo "[FAIL] no listener on target:9000 - run setup.sh first"
  exit 1
fi

echo "[check] client -> target:9000 via the special path"
OUT=$(sudo ip netns exec client bash -c 'echo hi | timeout 3 nc -w3 10.30.0.2 9000' 2>/dev/null || true)
echo "      response: ${OUT:-<none>}"
if [ "$OUT" = "TARGET-SERVICE-OK" ]; then
  echo "[PASS] client reached target - marked traffic is being policy-routed."
  exit 0
else
  echo "[FAIL] client could not reach target - marked traffic isn't reaching table 100."
  exit 1
fi
