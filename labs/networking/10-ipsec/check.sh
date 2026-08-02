#!/usr/bin/env bash
# Lab 10 (IPsec) — verifies the strongSwan site-to-site tunnel is
# ESTABLISHED with an active IPsec SA, and that hostA can actually reach
# hostB across it.
set -uo pipefail

LAB="ipsec-lab"
HOSTA="clab-${LAB}-hostA"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
HOSTB="clab-${LAB}-hostB"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying containers are running..."
for c in "$HOSTA" "$R1" "$R2" "$HOSTB"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (deploy the topology first)"
done

echo "[check] checking strongSwan SA status on r1..."
STATUS=$(docker exec "$R1" ipsec statusall 2>/dev/null)
echo "$STATUS" | grep -q "site-to-site" || fail "no 'site-to-site' connection found in ipsec statusall on r1"
echo "$STATUS" | grep "site-to-site" | grep -q "ESTABLISHED" || fail "'site-to-site' connection is not ESTABLISHED on r1"

echo "[check] checking xfrm state has an active ESP SA on r1..."
docker exec "$R1" ip xfrm state 2>/dev/null | grep -q "proto esp" || fail "no ESP transform state found in 'ip xfrm state' on r1"

echo "[check] verifying underlay reachability r1 -> r2 (172.16.0.2)..."
docker exec "$R1" ping -c 2 -W 2 172.16.0.2 >/dev/null 2>&1 || fail "r1 cannot ping r2 over the underlay"

echo "[check] verifying end-to-end reachability hostA -> hostB (10.2.2.10) through the tunnel..."
docker exec "$HOSTA" ping -c 2 -W 2 10.2.2.10 >/dev/null 2>&1 || fail "hostA cannot ping hostB through the IPsec tunnel"

echo "[PASS] IPsec tunnel is ESTABLISHED with an active SA, and hostA can reach hostB end-to-end"
exit 0
