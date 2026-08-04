#!/usr/bin/env bash
# Lab 15 (SYN Flood) — verifies the healthy state: no flood currently
# running, SYN cookies enabled on the victim, and a real client can
# complete a TCP handshake to the listener quickly.
set -uo pipefail

LAB="syn-flood"
ATTACKER="clab-${LAB}-attacker"
VICTIM="clab-${LAB}-victim"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying containers are running..."
for c in "$ATTACKER" "$VICTIM"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (deploy the topology first)"
done

echo "[check] verifying no hping3 flood is currently running..."
if docker exec "$ATTACKER" pgrep hping3 >/dev/null 2>&1; then
  fail "hping3 flood is still running on attacker (pkill hping3 to stop it)"
fi

echo "[check] verifying SYN cookies are enabled on victim..."
cookies=$(docker exec "$VICTIM" sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)
[ "$cookies" = "1" ] || fail "net.ipv4.tcp_syncookies=$cookies on victim, expected 1 — see Challenges A/B"

echo "[check] verifying the listener is up on victim:8080..."
docker exec "$VICTIM" bash -c "ss -ltn 2>/dev/null | grep -q ':8080'" \
  || fail "nothing listening on victim:8080"

echo "[check] verifying a real client can complete a handshake..."
if ! docker exec "$ATTACKER" nc -zv -w 3 10.0.0.20 8080 >/dev/null 2>&1; then
  fail "nc connect to victim:8080 failed/timed out"
fi

echo "[PASS] no flood running, SYN cookies on, legitimate connections succeed"
exit 0
