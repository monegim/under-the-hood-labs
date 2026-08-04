#!/usr/bin/env bash
# Lab 16 (Asymmetric Routing) — verifies the healthy end-of-Steps state:
# routing is symmetric (both directions via r1), r1's FORWARD policy is
# permissive, and both ping and a real HTTP request succeed end to end.
set -uo pipefail

LAB="asym-routing"
CLIENT="clab-${LAB}-client"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
SERVER="clab-${LAB}-server"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying containers are running..."
for c in "$CLIENT" "clab-${LAB}-switch-a" "$R1" "$R2" "clab-${LAB}-switch-b" "$SERVER"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (deploy the topology first)"
done

echo "[check] verifying server's return route to client is via r1 (symmetric)..."
docker exec "$SERVER" ip route show 10.0.1.0/24 2>/dev/null | grep -q "10.0.2.1" \
  || fail "server's route to 10.0.1.0/24 is not via r1 (10.0.2.1) — routing is asymmetric, see Challenge A"

echo "[check] verifying r1's FORWARD policy is permissive..."
policy=$(docker exec "$R1" iptables -L FORWARD -n 2>/dev/null | head -1)
echo "$policy" | grep -qi "DROP" && fail "r1's FORWARD policy is DROP — see Challenge B"

echo "[check] verifying the HTTP listener is running on the server..."
docker exec "$SERVER" pgrep -f "http.server 8080" >/dev/null 2>&1 \
  || fail "no http.server listener found on server:8080"

echo "[check] verifying ping succeeds..."
docker exec "$CLIENT" ping -c 2 -W 2 10.0.2.10 >/dev/null 2>&1 || fail "ping client -> server failed"

echo "[check] verifying a real HTTP request completes..."
docker exec "$CLIENT" curl -s --max-time 5 http://10.0.2.10:8080/ -o /dev/null \
  || fail "curl client -> server:8080 failed"

echo "[PASS] routing is symmetric, firewalls are not interfering, end-to-end connectivity works"
exit 0
