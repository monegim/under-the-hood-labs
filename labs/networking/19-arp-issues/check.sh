#!/usr/bin/env bash
# Lab 19 (ARP Issues) — verifies the healthy baseline: exactly one server
# holds the VIP, the client's ARP cache for the VIP matches whichever
# server actually holds it, and the VIP is reachable.
set -uo pipefail

LAB="arp-lab"
CLIENT="clab-${LAB}-client"
SWITCH="clab-${LAB}-switch"
SERVER_A="clab-${LAB}-server-a"
SERVER_B="clab-${LAB}-server-b"
VIP="10.0.0.100"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying containers are running..."
for c in "$CLIENT" "$SWITCH" "$SERVER_A" "$SERVER_B"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (deploy the topology first)"
done

a_has_vip=$(docker exec "$SERVER_A" ip addr show eth1 2>/dev/null | grep -c "$VIP" || true)
b_has_vip=$(docker exec "$SERVER_B" ip addr show eth1 2>/dev/null | grep -c "$VIP" || true)

echo "[check] verifying exactly one server holds the VIP..."
total=$((a_has_vip + b_has_vip))
if [ "$total" -eq 0 ]; then
  fail "neither server-a nor server-b currently holds $VIP"
elif [ "$total" -gt 1 ]; then
  fail "both server-a and server-b hold $VIP simultaneously — see Challenge B"
fi

if [ "$a_has_vip" -eq 1 ]; then
  owner="$SERVER_A"; owner_name="server-a"
else
  owner="$SERVER_B"; owner_name="server-b"
fi
owner_mac=$(docker exec "$owner" bash -c "ip link show eth1 | awk '/link\/ether/{print \$2}'")
echo "[check] VIP is currently held by $owner_name ($owner_mac)"

echo "[check] verifying client's ARP cache matches the actual VIP owner..."
docker exec "$CLIENT" ping -c 1 -W 2 "$VIP" >/dev/null 2>&1 || true
cached_mac=$(docker exec "$CLIENT" ip neigh show "$VIP" 2>/dev/null | awk '{print $5}')
if [ "$cached_mac" != "$owner_mac" ]; then
  fail "client's cached MAC for VIP ($cached_mac) does not match the real owner ($owner_mac) — see Challenge A"
fi

echo "[check] verifying the VIP is actually reachable from the client..."
docker exec "$CLIENT" ping -c 2 -W 2 "$VIP" >/dev/null 2>&1 || fail "client cannot reach the VIP"

echo "[PASS] exactly one VIP owner ($owner_name), client's ARP cache is correct, VIP is reachable"
exit 0
