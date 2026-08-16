#!/usr/bin/env bash
set -uo pipefail

# Lab 28 check - verifies port 9090 is blocked over BOTH IPv4 and IPv6
# from ns1 - proving the two rule sets are actually in parity, not just
# that IPv4 (the one everyone remembers to check) is locked down.

fail=0

echo "[check] IPv4: ns1 -> ns2:9090 (10.20.0.2) should be BLOCKED"
if timeout 3 sudo ip netns exec ns1 bash -c 'echo hi | nc -w2 10.20.0.2 9090' >/dev/null 2>&1; then
    echo "[FAIL] IPv4 access succeeded — port 9090 is not blocked over IPv4."
    fail=1
else
    echo "[PASS] IPv4 access is blocked."
fi

echo "[check] IPv6: ns1 -> ns2:9090 (fd00:26::2) should be BLOCKED"
if timeout 3 sudo ip netns exec ns1 bash -c 'echo hi | nc -6 -w2 fd00:26::2 9090' >/dev/null 2>&1; then
    echo "[FAIL] IPv6 access succeeded — port 9090 is still wide open over IPv6."
    fail=1
else
    echo "[PASS] IPv6 access is blocked."
fi

echo "[check] is global IPv6 disabled as a workaround? (that would be the WRONG fix)"
DISABLED=$(sudo ip netns exec ns2 sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "0")
if [ "$DISABLED" = "1" ]; then
    echo "[FAIL] IPv6 is globally disabled in ns2 — that's the blunt workaround, not the targeted fix (ip6tables rule parity)."
    fail=1
else
    echo "[PASS] IPv6 is still enabled — the fix was a real ip6tables rule, not disabling the stack."
fi

if [ "$fail" -eq 0 ]; then
    echo "[PASS] IPv4 and IPv6 rules are in parity, and IPv6 itself wasn't disabled to get there."
    exit 0
else
    echo "[FAIL] see details above."
    exit 1
fi
