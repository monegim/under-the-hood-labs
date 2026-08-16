#!/usr/bin/env bash
set -uo pipefail

# Lab 27 check - verifies both halves of the real fix: the rule is
# CURRENTLY active, AND it's actually persisted somewhere that will
# reload it at the next real boot (not just backed up to a file nobody
# reads at startup).

fail=0

echo "[check] is port 9999 currently blocked?"
if timeout 3 bash -c 'echo hi | nc -w2 127.0.0.1 9999' >/dev/null 2>&1; then
    echo "[FAIL] port 9999 is NOT blocked right now."
    fail=1
else
    echo "[PASS] port 9999 is currently blocked."
fi

echo "[check] is the DROP rule actually in the live INPUT chain?"
if sudo iptables -L INPUT -n | grep -q "DROP.*dpt:9999\|dpt:9999.*DROP"; then
    echo "[PASS] DROP rule for port 9999 is present in INPUT."
else
    echo "[FAIL] no DROP rule for port 9999 found in the live INPUT chain."
    fail=1
fi

echo "[check] is the rule persisted somewhere that survives a reboot?"
PERSISTED=0
if [ -f /etc/iptables/rules.v4 ] && grep -q -- "--dport 9999" /etc/iptables/rules.v4 2>/dev/null; then
    PERSISTED=1
fi
if [ "$PERSISTED" -eq 1 ]; then
    echo "[check] found the rule in /etc/iptables/rules.v4."
else
    echo "[FAIL] the rule is not present in /etc/iptables/rules.v4 — it would NOT survive a real reboot."
    fail=1
fi

echo "[check] is anything actually enabled to load that file at boot?"
if systemctl is-enabled netfilter-persistent >/dev/null 2>&1; then
    echo "[PASS] netfilter-persistent is enabled — rules will load at boot."
else
    echo "[FAIL] netfilter-persistent is not enabled — a saved rules file alone won't be loaded automatically."
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "[PASS] rule is live, persisted, and will actually survive a reboot."
    exit 0
else
    echo "[FAIL] see details above."
    exit 1
fi
