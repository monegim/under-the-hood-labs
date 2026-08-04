#!/usr/bin/env bash
# Lab 20 (NAT Port Exhaustion) - verifies the dual-IP SNAT fix from Step 7
# is in place and healthy: 8 concurrent connections through a 10-port
# combined pool (5 ports each on two external IPs) all succeed, and
# sessions are actually split across both external IPs.
set -uo pipefail

HOST_INT="clab-natexh-host-int"
ROUTER="clab-natexh-router"
HOST_EXT="clab-natexh-host-ext"

fail=0

echo "[check] verifying containers are running..."
for c in "$HOST_INT" "$ROUTER" "$HOST_EXT"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  if [ "$status" != "true" ]; then
    echo "[FAIL] container $c is not running (deploy the topology first)"
    exit 1
  fi
done

echo "[check] router ip_forward enabled"
fwd=$(docker exec "$ROUTER" sysctl -n net.ipv4.ip_forward 2>/dev/null)
if [ "$fwd" = "1" ]; then
  echo "[PASS] net.ipv4.ip_forward=1 on router"
else
  echo "[FAIL] net.ipv4.ip_forward is not 1 on router (got: '$fwd')"
  fail=1
fi

echo "[check] both external IPs present on router eth2"
addrs=$(docker exec "$ROUTER" ip -4 addr show eth2 2>/dev/null)
for ip in "203.0.113.1" "203.0.113.21"; do
  if echo "$addrs" | grep -q "$ip"; then
    echo "[PASS] $ip present on eth2"
  else
    echo "[FAIL] $ip missing from eth2 - the dual-IP fix isn't applied"
    fail=1
  fi
done

echo "[check] firing 8 concurrent connections through the NAT pool..."
results=$(mktemp)
for i in $(seq 1 8); do
  ( docker exec "$HOST_INT" timeout 8 bash -c \
      'exec 3<>/dev/tcp/203.0.113.20/9000 && sleep 6' \
    && echo "OK" || echo "FAIL" ) >> "$results" &
done
wait

ok_count=$(grep -c OK "$results" || true)
rm -f "$results"

if [ "$ok_count" -eq 8 ]; then
  echo "[PASS] all 8 concurrent connections succeeded"
else
  echo "[FAIL] only $ok_count/8 connections succeeded (expected 8) - SNAT pool may be exhausted or misconfigured"
  fail=1
fi

echo "[check] verifying NAT sessions are split across both external IPs..."
sessions=$(docker exec "$ROUTER" conntrack -L -p tcp --dport 9000 2>/dev/null)
if echo "$sessions" | grep -q "203.0.113.1 " && echo "$sessions" | grep -q "203.0.113.21"; then
  echo "[PASS] NAT sessions observed via both 203.0.113.1 and 203.0.113.21"
else
  echo "[FAIL] NAT sessions are not split across both external IPs - check rule order (iptables -t nat -L POSTROUTING -n -v --line-numbers)"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[PASS] Lab 20 topology is healthy"
  exit 0
else
  echo "[FAIL] Lab 20 topology has issues (see above)"
  exit 1
fi
