#!/usr/bin/env bash
set -uo pipefail

# Lab 29 check - fires a rapid burst from the noisy client (ns1) and
# verifies most of it gets rejected, THEN verifies the well-behaved
# client (ns3) can still get through despite ns1's flood — proving
# rate limiting is both actually engaged AND scoped per-source, not a
# shared global budget one noisy client can exhaust for everyone.

fail=0

if ! sudo ip netns exec ns2 pgrep -f "nc -l 7000" >/dev/null 2>&1; then
    echo "[FAIL] no listener on ns2:7000 — run setup.sh first"
    exit 1
fi

echo "[check] flooding from ns1 (noisy client) — 15 rapid attempts..."
NS1_OK=0
for i in $(seq 1 15); do
    if timeout 2 sudo ip netns exec ns1 bash -c 'echo hi | nc -w1 10.30.0.2 7000' >/dev/null 2>&1; then
        NS1_OK=$((NS1_OK + 1))
    fi
done
echo "[check] ns1 succeeded $NS1_OK/15 times"
if [ "$NS1_OK" -ge 12 ]; then
    echo "[FAIL] almost everything from ns1 succeeded — no meaningful rate limiting is in effect."
    fail=1
fi

echo "[check] does ns3 (well-behaved client) still get through, despite ns1's flood?"
if timeout 3 sudo ip netns exec ns3 bash -c 'echo hi | nc -w2 10.30.0.2 7000' >/dev/null 2>&1; then
    echo "[PASS] ns3 got through."
else
    echo "[FAIL] ns3 was also blocked — the rate limit is a shared global budget, not per-source; ns1's flood locked ns3 out too."
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "[PASS] rate limiting is engaged and correctly scoped per-source."
    exit 0
else
    echo "[FAIL] see details above."
    exit 1
fi
