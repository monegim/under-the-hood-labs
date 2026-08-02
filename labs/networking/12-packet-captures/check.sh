#!/usr/bin/env bash
# Lab 12 (Packet Captures) — verifies the baseline "clean handshake" state:
# the HTTP listener is running on the server, no firewall rules are
# silently dropping/rejecting traffic on the server or on r1, and the
# client can actually complete a request end-to-end.
set -uo pipefail

LAB="pcap-lab"
CLIENT="clab-${LAB}-client"
R1="clab-${LAB}-r1"
SERVER="clab-${LAB}-server"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying containers are running..."
for c in "$CLIENT" "$R1" "$SERVER"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (deploy the topology first)"
done

echo "[check] verifying the HTTP listener is running on the server..."
docker exec "$SERVER" pgrep -f "http.server 8080" >/dev/null 2>&1 || fail "no http.server listener found on port 8080 on server"

echo "[check] verifying no DROP rule is silently blocking the server's own port 8080 (Challenge A)..."
if docker exec "$SERVER" iptables -C INPUT -p tcp --dport 8080 -j DROP 2>/dev/null; then
  fail "server has an INPUT DROP rule for tcp/8080 — see Challenge A"
fi

echo "[check] verifying no REJECT rule on r1 is injecting RSTs for port 8080 (Challenge B)..."
if docker exec "$R1" iptables -C FORWARD -p tcp --dport 8080 -j REJECT --reject-with tcp-reset 2>/dev/null; then
  fail "r1 has a FORWARD REJECT rule for tcp/8080 — see Challenge B"
fi

echo "[check] verifying the client can complete an end-to-end request..."
docker exec "$CLIENT" curl -s --max-time 5 http://10.0.2.10:8080/ -o /dev/null || fail "client curl to server:8080 failed"

echo "[PASS] listener is up, no firewall rules interfering, and the client can reach the server"
exit 0
