#!/usr/bin/env bash
set -uo pipefail

# Lab 3 - Static Routing: verify host1 <-> host2 end-to-end connectivity
# across r1/r2, the exact test the README uses in Step 5.

fail=0

echo "[check] host1 -> host2 (10.0.1.10 -> 10.0.2.10)"
if docker exec clab-static-routing-host1 ping -c 3 -W 2 10.0.2.10 >/dev/null 2>&1; then
  echo "[PASS] host1 can ping host2"
else
  echo "[FAIL] host1 cannot ping host2"
  fail=1
fi

echo "[check] host2 -> host1 (10.0.2.10 -> 10.0.1.10)"
if docker exec clab-static-routing-host2 ping -c 3 -W 2 10.0.1.10 >/dev/null 2>&1; then
  echo "[PASS] host2 can ping host1"
else
  echo "[FAIL] host2 cannot ping host1"
  fail=1
fi

echo "[check] r1 has route to 10.0.2.0/24"
if docker exec clab-static-routing-r1 vtysh -c "show ip route 10.0.2.0/24" 2>/dev/null | grep -q "10.0.2.0/24"; then
  echo "[PASS] r1 has a route to 10.0.2.0/24"
else
  echo "[FAIL] r1 is missing a route to 10.0.2.0/24"
  fail=1
fi

echo "[check] r2 has route to 10.0.1.0/24"
if docker exec clab-static-routing-r2 vtysh -c "show ip route 10.0.1.0/24" 2>/dev/null | grep -q "10.0.1.0/24"; then
  echo "[PASS] r2 has a route to 10.0.1.0/24"
else
  echo "[FAIL] r2 is missing a route to 10.0.1.0/24"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[PASS] Lab 3 topology is healthy"
  exit 0
else
  echo "[FAIL] Lab 3 topology has issues (see above)"
  exit 1
fi
