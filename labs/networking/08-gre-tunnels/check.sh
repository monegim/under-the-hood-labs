#!/usr/bin/env bash
# Lab 8 (GRE Tunnels) — verifies the GRE tunnel endpoints are correctly
# configured, the tunnel interface is up, routes exist into it, and hostA
# can actually reach hostB end-to-end through it.
set -uo pipefail

LAB="gre-lab"
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

echo "[check] verifying gre1 tunnel endpoints on r1 and r2..."
R1_TUNNEL=$(docker exec "$R1" ip -d tunnel show gre1 2>/dev/null)
echo "$R1_TUNNEL" | grep -q "remote 172.16.0.2" || fail "r1's gre1 remote is not 172.16.0.2 (got: $R1_TUNNEL)"
echo "$R1_TUNNEL" | grep -q "local 172.16.0.1" || fail "r1's gre1 local is not 172.16.0.1 (got: $R1_TUNNEL)"

R2_TUNNEL=$(docker exec "$R2" ip -d tunnel show gre1 2>/dev/null)
echo "$R2_TUNNEL" | grep -q "remote 172.16.0.1" || fail "r2's gre1 remote is not 172.16.0.1 (got: $R2_TUNNEL)"
echo "$R2_TUNNEL" | grep -q "local 172.16.0.2" || fail "r2's gre1 local is not 172.16.0.2 (got: $R2_TUNNEL)"

echo "[check] verifying gre1 is up on both routers..."
docker exec "$R1" ip link show gre1 2>/dev/null | grep -q "UP" || fail "r1's gre1 is not UP"
docker exec "$R2" ip link show gre1 2>/dev/null | grep -q "UP" || fail "r2's gre1 is not UP"

echo "[check] verifying routes into the tunnel exist..."
docker exec "$R1" ip route show 10.2.2.0/24 2>/dev/null | grep -q "dev gre1" || fail "r1 is missing route 10.2.2.0/24 via gre1"
docker exec "$R2" ip route show 10.1.1.0/24 2>/dev/null | grep -q "dev gre1" || fail "r2 is missing route 10.1.1.0/24 via gre1"

echo "[check] verifying tunnel-endpoint-to-tunnel-endpoint reachability (r1 -> 192.168.100.2)..."
docker exec "$R1" ping -c 2 -W 2 192.168.100.2 >/dev/null 2>&1 || fail "r1 cannot ping r2 across gre1"

echo "[check] verifying end-to-end reachability hostA -> hostB (10.2.2.10)..."
docker exec "$HOSTA" ping -c 2 -W 2 10.2.2.10 >/dev/null 2>&1 || fail "hostA cannot ping hostB"

echo "[PASS] GRE tunnel is healthy and hostA can reach hostB end-to-end"
exit 0
