#!/usr/bin/env bash
# Lab 7 (BGP) — verifies the eBGP peering is Established AND that routes
# are actually being learned, not just that the session is up.
set -uo pipefail

LAB="bgp-lab"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
R3="clab-${LAB}-r3"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying containers are running..."
for c in "$R1" "$R2" "$R3"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (deploy the topology first)"
done

echo "[check] checking eBGP session state on r2 (show bgp summary)..."
SUMMARY=$(docker exec "$R2" vtysh -c "show bgp summary" 2>/dev/null)
echo "$SUMMARY"

for neighbor in "10.12.0.1" "10.23.0.2"; do
  line=$(echo "$SUMMARY" | grep -E "^${neighbor//./\\.}[[:space:]]")
  if [ -z "$line" ]; then
    fail "neighbor $neighbor not found in 'show bgp summary' output on r2"
  fi
  if echo "$line" | grep -qE 'Idle|Active|Connect|OpenSent|OpenConfirm'; then
    fail "neighbor $neighbor is not Established (state: $(echo "$line" | awk '{print $NF}'))"
  fi
done
echo "[check] both eBGP sessions on r2 are Established"

echo "[check] checking r3 learned 1.1.1.1/32 via BGP (not just connected)..."
ROUTE=$(docker exec "$R3" vtysh -c "show ip route bgp" 2>/dev/null)
echo "$ROUTE" | grep -q "1.1.1.1" || fail "r3 does not have 1.1.1.1/32 in 'show ip route bgp' — session may be up but routes aren't being advertised/redistributed"

echo "[check] verifying end-to-end reachability r3 -> 1.1.1.1 (r1's loopback)..."
docker exec "$R3" ping -c 2 -W 2 1.1.1.1 >/dev/null 2>&1 || fail "r3 cannot ping 1.1.1.1"

echo "[PASS] eBGP sessions Established, 1.1.1.1/32 learned via BGP on r3, and end-to-end reachable"
exit 0
