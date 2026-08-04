#!/usr/bin/env bash
# Lab 14 (TCP Retransmissions) — verifies the healthy baseline: no netem
# loss configured on the client's link, the server's iperf3 process is
# actually running (not stopped), and a real transfer completes with a
# low retransmit count.
set -uo pipefail

LAB="tcp-retrans"
CLIENT="clab-${LAB}-client"
SERVER="clab-${LAB}-server"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying containers are running..."
for c in "$CLIENT" "$SERVER"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || fail "container $c is not running (deploy the topology first)"
done

echo "[check] verifying no netem qdisc is injecting loss on the client (Challenge A)..."
if docker exec "$CLIENT" tc qdisc show dev eth1 2>/dev/null | grep -q netem; then
  fail "client eth1 still has a netem qdisc attached — see Challenge A"
fi

echo "[check] verifying the server's iperf3 process is running, not stopped (Challenge B)..."
state=$(docker exec "$SERVER" bash -c "ps -o stat= -C iperf3 2>/dev/null | head -1")
if [ -z "$state" ]; then
  echo "[check] no iperf3 server running yet, starting one..."
  docker exec -d "$SERVER" iperf3 -s
  sleep 1
elif echo "$state" | grep -q "T"; then
  fail "iperf3 server process is STOPPED (state T) — see Challenge B"
fi

echo "[check] running a real transfer and checking retransmit count..."
docker exec "$CLIENT" iperf3 -c 10.0.0.20 -t 3 >/dev/null 2>&1 || fail "iperf3 transfer failed to complete"

retrans=$(docker exec "$CLIENT" ss -ti dst 10.0.0.20 2>/dev/null | grep -o "retrans:[0-9]*/[0-9]*" | head -1 | cut -d/ -f2)
retrans=${retrans:-0}
if [ "$retrans" -gt 20 ]; then
  fail "retransmit count is unexpectedly high ($retrans) — link may still be lossy"
fi

echo "[PASS] link is clean, receiver is responsive, transfer completed with low retransmits"
exit 0
