#!/usr/bin/env bash
set -uo pipefail

# Lab 5 - Firewalls: verify the FORWARD chain is default-DROP with the
# specific ACCEPT rules from Steps 3-5, and that both ping and TCP/80
# actually pass end to end through fw - the same tests the README uses.

fail=0

echo "[check] fw FORWARD chain default policy is DROP"
if docker exec clab-firewalls-fw iptables -L FORWARD -n 2>/dev/null | head -1 | grep -q "policy DROP"; then
  echo "[PASS] FORWARD policy is DROP"
else
  echo "[FAIL] FORWARD policy is not DROP"
  fail=1
fi

echo "[check] fw FORWARD chain has ESTABLISHED,RELATED accept rule"
if docker exec clab-firewalls-fw iptables -L FORWARD -n 2>/dev/null | grep -q "ESTABLISHED,RELATED"; then
  echo "[PASS] stateful return-traffic rule present"
else
  echo "[FAIL] no ESTABLISHED,RELATED accept rule in FORWARD"
  fail=1
fi

echo "[check] client -> server ping (10.10.1.10 -> 10.10.2.10)"
if docker exec clab-firewalls-client ping -c 2 -W 2 10.10.2.10 >/dev/null 2>&1; then
  echo "[PASS] client can ping server through fw"
else
  echo "[FAIL] client cannot ping server through fw"
  fail=1
fi

echo "[check] client -> server TCP/80"
docker exec clab-firewalls-server sh -c 'pgrep -f "nc -lp 80" >/dev/null 2>&1 || nohup nc -lp 80 >/dev/null 2>&1 &' >/dev/null 2>&1
sleep 1
if docker exec clab-firewalls-client sh -c 'echo healthcheck | nc -w2 10.10.2.10 80' >/dev/null 2>&1; then
  echo "[PASS] client reached server:80 through fw"
else
  echo "[FAIL] client could not reach server:80 through fw"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[PASS] Lab 5 topology is healthy"
  exit 0
else
  echo "[FAIL] Lab 5 topology has issues (see above)"
  exit 1
fi
