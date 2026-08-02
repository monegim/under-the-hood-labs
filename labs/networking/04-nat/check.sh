#!/usr/bin/env bash
set -uo pipefail

# Lab 4 - NAT: verify ip_forward is on, MASQUERADE is actually being hit
# (not just present), and both the outbound (MASQUERADE) and inbound
# (DNAT) paths work end to end - the same tests the README uses in
# Steps 4-6.

fail=0

echo "[check] router ip_forward enabled"
fwd=$(docker exec clab-nat-router sysctl -n net.ipv4.ip_forward 2>/dev/null)
if [ "$fwd" = "1" ]; then
  echo "[PASS] net.ipv4.ip_forward=1 on router"
else
  echo "[FAIL] net.ipv4.ip_forward is not 1 on router (got: '$fwd')"
  fail=1
fi

echo "[check] outbound: host-int -> host-ext (203.0.113.10) via MASQUERADE"
if docker exec clab-nat-host-int ping -c 3 -W 2 203.0.113.10 >/dev/null 2>&1; then
  echo "[PASS] host-int can ping host-ext"
else
  echo "[FAIL] host-int cannot ping host-ext"
  fail=1
fi

echo "[check] MASQUERADE rule on eth2 (external interface) is actually matching traffic"
rule_line=$(docker exec clab-nat-router iptables -t nat -L POSTROUTING -n -v 2>/dev/null | grep MASQUERADE || true)
if [ -z "$rule_line" ]; then
  echo "[FAIL] no MASQUERADE rule found in nat/POSTROUTING"
  fail=1
elif echo "$rule_line" | awk '{print $1}' | grep -qE '^[1-9]'; then
  echo "[PASS] MASQUERADE rule present and has nonzero packet count: $rule_line"
else
  echo "[FAIL] MASQUERADE rule present but has 0 packets matched (wrong interface?): $rule_line"
  fail=1
fi

echo "[check] inbound: DNAT of router:8080 -> host-int:8080"
docker exec clab-nat-host-int sh -c 'pgrep -f "nc -lp 8080" >/dev/null 2>&1 || nohup nc -lp 8080 >/dev/null 2>&1 &' >/dev/null 2>&1
sleep 1
if docker exec clab-nat-host-ext sh -c 'echo healthcheck | nc -w2 203.0.113.1 8080' >/dev/null 2>&1; then
  echo "[PASS] host-ext reached host-int:8080 via router's DNAT"
else
  echo "[FAIL] host-ext could not reach host-int:8080 via DNAT"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[PASS] Lab 4 topology is healthy"
  exit 0
else
  echo "[FAIL] Lab 4 topology has issues (see above)"
  exit 1
fi
