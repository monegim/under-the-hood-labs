#!/usr/bin/env bash
# Lab 18 (DHCP Failure) — verifies the healthy baseline: the DHCP server
# is running with its pool not artificially exhausted, and the client can
# successfully obtain a fresh lease right now.
set -uo pipefail

LAB="dhcp-lab"
CLIENT="clab-${LAB}-client"
DHCPSERVER="clab-${LAB}-dhcp-server"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying containers are running..."
for c in "$CLIENT" "$DHCPSERVER"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (deploy the topology first)"
done

echo "[check] verifying dnsmasq is running on dhcp-server..."
docker exec "$DHCPSERVER" pgrep dnsmasq >/dev/null 2>&1 \
  || fail "no dnsmasq process on dhcp-server — see Challenge B"

echo "[check] verifying the pool isn't pre-occupied by phantom leases..."
if docker exec "$DHCPSERVER" bash -c "grep -q phantom /var/lib/misc/dnsmasq.leases 2>/dev/null"; then
  fail "phantom leases still occupy the pool — see Challenge A"
fi

echo "[check] releasing any existing client lease and requesting a fresh one..."
docker exec "$CLIENT" dhclient -r eth1 >/dev/null 2>&1 || true
sleep 1
if ! docker exec "$CLIENT" dhclient -v -1 eth1 2>&1 | grep -q "DHCPACK"; then
  fail "client did not receive a DHCPACK — DHCP server may be unreachable or pool exhausted"
fi

echo "[check] verifying the client has a usable IPv4 address..."
docker exec "$CLIENT" ip addr show eth1 | grep -q "inet 10.50.0" \
  || fail "client has no 10.50.0.0/24 address after dhclient"

echo "[PASS] DHCP server is healthy, pool has room, client obtained a lease"
exit 0
