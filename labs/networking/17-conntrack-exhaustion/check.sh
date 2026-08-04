#!/usr/bin/env bash
# Lab 17 (Conntrack Exhaustion) — verifies the healthy baseline: r1's
# conntrack table is not full, the listener is running on the server, and
# a brand-new connection completes without hanging.
set -uo pipefail

LAB="conntrack-lab"
CLIENT="clab-${LAB}-client"
R1="clab-${LAB}-r1"
SERVER="clab-${LAB}-server"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying containers are running..."
for c in "$CLIENT" "$R1" "$SERVER"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (deploy the topology first)"
done

echo "[check] verifying the listener is running on the server..."
docker exec "$SERVER" pgrep -f "python3" >/dev/null 2>&1 || fail "no python3 listener found on server"

echo "[check] verifying r1's conntrack table is not full..."
count=$(docker exec "$R1" sysctl -n net.netfilter.nf_conntrack_count 2>/dev/null)
max=$(docker exec "$R1" sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null)
[ -n "$count" ] && [ -n "$max" ] || fail "could not read nf_conntrack_count/max on r1"
if [ "$count" -ge "$max" ]; then
  fail "r1's conntrack table is full ($count/$max) — see Challenges A/B"
fi

echo "[check] verifying a brand-new connection completes..."
if ! docker exec "$CLIENT" bash -c 'timeout 5 bash -c "exec 3<>/dev/tcp/10.0.2.10/9090 && echo ok"' >/dev/null 2>&1; then
  fail "a new connection to server:9090 did not complete"
fi

echo "[PASS] conntrack table has headroom ($count/$max), new connections succeed"
exit 0
