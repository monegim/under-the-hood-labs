#!/usr/bin/env bash
# Lab 13 (Broken DNS) — verifies the healthy baseline: resolver and
# upstream dnsmasq processes are both running, the client's resolv.conf
# points at the real resolver, and app.internal actually resolves
# end-to-end with a NOERROR status.
set -uo pipefail

LAB="broken-dns"
CLIENT="clab-${LAB}-client"
RESOLVER="clab-${LAB}-resolver"
UPSTREAM="clab-${LAB}-upstream"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying containers are running..."
for c in "$CLIENT" "$RESOLVER" "$UPSTREAM"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (deploy the topology first)"
done

echo "[check] verifying resolv.conf on client points at the real resolver (10.0.1.1)..."
docker exec "$CLIENT" grep -q "nameserver 10.0.1.1" /etc/resolv.conf 2>/dev/null \
  || fail "client's /etc/resolv.conf does not point at 10.0.1.1 — see Challenge A"

echo "[check] verifying dnsmasq is running on resolver..."
docker exec "$RESOLVER" pgrep dnsmasq >/dev/null 2>&1 || fail "no dnsmasq process on resolver"

echo "[check] verifying dnsmasq is running on upstream..."
docker exec "$UPSTREAM" pgrep dnsmasq >/dev/null 2>&1 || fail "no dnsmasq process on upstream — see Challenge B"

echo "[check] verifying app.internal actually resolves end-to-end..."
answer=$(docker exec "$CLIENT" dig +short +time=3 +tries=1 app.internal 2>/dev/null)
[ -n "$answer" ] || fail "dig app.internal returned no answer"

echo "[check] verifying dig reports NOERROR (not SERVFAIL)..."
status=$(docker exec "$CLIENT" dig +time=3 +tries=1 app.internal 2>/dev/null | grep -o "status: [A-Z]*")
echo "$status" | grep -q "NOERROR" || fail "dig status was '$status', not NOERROR — see Challenge B"

echo "[PASS] resolver and upstream are healthy, client resolves app.internal correctly"
exit 0
