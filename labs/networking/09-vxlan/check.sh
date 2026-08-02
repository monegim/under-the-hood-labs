#!/usr/bin/env bash
# Lab 9 (VXLAN) — verifies the VXLAN overlay is correctly built: matching
# VNI on both VTEPs, wildcard FDB entries programmed on both sides, the
# bridge is assembled correctly, and hostA can reach hostB across the
# overlay.
set -uo pipefail

LAB="vxlan-lab"
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

echo "[check] verifying vxlan10 has VNI 10 on both r1 and r2..."
docker exec "$R1" ip -d link show vxlan10 2>/dev/null | grep -q "vxlan id 10 " || fail "r1's vxlan10 is not VNI 10"
docker exec "$R2" ip -d link show vxlan10 2>/dev/null | grep -q "vxlan id 10 " || fail "r2's vxlan10 is not VNI 10 (VNI mismatch — see Challenge A)"

echo "[check] verifying wildcard FDB entries are programmed on both VTEPs..."
docker exec "$R1" bridge fdb show dev vxlan10 2>/dev/null | grep -q "00:00:00:00:00:00 dst 172.16.0.2" \
  || fail "r1 is missing the wildcard FDB entry pointing at r2 (172.16.0.2) — see Challenge B"
docker exec "$R2" bridge fdb show dev vxlan10 2>/dev/null | grep -q "00:00:00:00:00:00 dst 172.16.0.1" \
  || fail "r2 is missing the wildcard FDB entry pointing at r1 (172.16.0.1)"

echo "[check] verifying vxlan10 is bridged into br0 on both routers..."
docker exec "$R1" ip link show vxlan10 2>/dev/null | grep -q "master br0" || fail "r1's vxlan10 is not enslaved to br0"
docker exec "$R2" ip link show vxlan10 2>/dev/null | grep -q "master br0" || fail "r2's vxlan10 is not enslaved to br0"

echo "[check] verifying underlay reachability r1 -> r2 (172.16.0.2)..."
docker exec "$R1" ping -c 2 -W 2 172.16.0.2 >/dev/null 2>&1 || fail "r1 cannot ping r2 over the underlay"

echo "[check] verifying end-to-end reachability hostA -> hostB (10.0.0.20) over the overlay..."
docker exec "$HOSTA" ping -c 2 -W 2 10.0.0.20 >/dev/null 2>&1 || fail "hostA cannot ping hostB over the VXLAN overlay"

echo "[PASS] VXLAN overlay is healthy and hostA can reach hostB end-to-end"
exit 0
