#!/usr/bin/env bash
set -uo pipefail

# Lab 6 - OSPF: verify both adjacencies (r1-r2, r2-r3) are Full and
# host1 -> host2 works end to end via routes OSPF installed itself -
# the same tests the README uses in Step 5.

fail=0

echo "[check] r2 OSPF neighbor state"
r2_neigh=$(docker exec clab-ospf-r2 vtysh -c "show ip ospf neighbor" 2>/dev/null)
if echo "$r2_neigh" | grep -q "1.1.1.1" && echo "$r2_neigh" | grep "1.1.1.1" | grep -qi "full"; then
  echo "[PASS] r2 <-> r1 adjacency is Full"
else
  echo "[FAIL] r2 <-> r1 adjacency is not Full"
  echo "$r2_neigh"
  fail=1
fi
if echo "$r2_neigh" | grep -q "3.3.3.3" && echo "$r2_neigh" | grep "3.3.3.3" | grep -qi "full"; then
  echo "[PASS] r2 <-> r3 adjacency is Full"
else
  echo "[FAIL] r2 <-> r3 adjacency is not Full"
  echo "$r2_neigh"
  fail=1
fi

echo "[check] r1 has OSPF-learned route to 10.0.3.0/24"
if docker exec clab-ospf-r1 vtysh -c "show ip route ospf" 2>/dev/null | grep -q "10.0.3.0/24"; then
  echo "[PASS] r1 learned 10.0.3.0/24 via OSPF"
else
  echo "[FAIL] r1 is missing OSPF route to 10.0.3.0/24"
  fail=1
fi

echo "[check] r3 has OSPF-learned route to 10.0.1.0/24"
if docker exec clab-ospf-r3 vtysh -c "show ip route ospf" 2>/dev/null | grep -q "10.0.1.0/24"; then
  echo "[PASS] r3 learned 10.0.1.0/24 via OSPF"
else
  echo "[FAIL] r3 is missing OSPF route to 10.0.1.0/24"
  fail=1
fi

echo "[check] host1 -> host2 (10.0.1.10 -> 10.0.3.10) end to end"
if docker exec clab-ospf-host1 ping -c 3 -W 2 10.0.3.10 >/dev/null 2>&1; then
  echo "[PASS] host1 can ping host2"
else
  echo "[FAIL] host1 cannot ping host2"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[PASS] Lab 6 topology is healthy"
  exit 0
else
  echo "[FAIL] Lab 6 topology has issues (see above)"
  exit 1
fi
