#!/usr/bin/env bash
# Lab 1 — Network Namespaces — check.sh
#
# Verifies the end state Steps 1-4 of README.md are supposed to produce:
#   - ns1 and ns2 exist
#   - veth1 (in ns1) and veth2 (in ns2) are UP and addressed
#     10.0.0.1/24 and 10.0.0.2/24 respectively
#   - ns1 can actually ping ns2 across the veth pair
#
# Usage: sudo bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 1 — Network Namespaces"
echo

# --- namespaces exist ---
if ip netns list 2>/dev/null | grep -qw ns1; then
    ok "namespace ns1 exists"
else
    bad "namespace ns1 does not exist (did you run Step 1?)"
fi

if ip netns list 2>/dev/null | grep -qw ns2; then
    ok "namespace ns2 exists"
else
    bad "namespace ns2 does not exist (did you run Step 1?)"
fi

# Bail early on the connectivity checks if either namespace is missing —
# everything below assumes both exist.
if [ "$FAIL" -gt 0 ]; then
    echo
    echo "[check] $PASS passed, $FAIL failed"
    exit 1
fi

# --- veth1 in ns1: state + address ---
VETH1_STATE=$(sudo ip netns exec ns1 ip -o link show veth1 2>/dev/null)
if [ -n "$VETH1_STATE" ]; then
    if echo "$VETH1_STATE" | grep -q "state UP"; then
        ok "veth1 (in ns1) is UP"
    else
        bad "veth1 (in ns1) exists but is not UP — try: sudo ip netns exec ns1 ip link set veth1 up"
    fi
else
    bad "veth1 does not exist in ns1 (did you run Step 2?)"
fi

if sudo ip netns exec ns1 ip -o addr show veth1 2>/dev/null | grep -q "10\.0\.0\.1/24"; then
    ok "veth1 (in ns1) has address 10.0.0.1/24"
else
    bad "veth1 (in ns1) does not have address 10.0.0.1/24"
fi

# --- veth2 in ns2: state + address ---
VETH2_STATE=$(sudo ip netns exec ns2 ip -o link show veth2 2>/dev/null)
if [ -n "$VETH2_STATE" ]; then
    if echo "$VETH2_STATE" | grep -q "state UP"; then
        ok "veth2 (in ns2) is UP"
    else
        bad "veth2 (in ns2) exists but is not UP — try: sudo ip netns exec ns2 ip link set veth2 up"
    fi
else
    bad "veth2 does not exist in ns2 (did you run Step 2?)"
fi

if sudo ip netns exec ns2 ip -o addr show veth2 2>/dev/null | grep -q "10\.0\.0\.2/24"; then
    ok "veth2 (in ns2) has address 10.0.0.2/24"
else
    bad "veth2 (in ns2) does not have address 10.0.0.2/24"
fi

# --- actual connectivity ---
if sudo ip netns exec ns1 ping -c 1 -W 2 10.0.0.2 >/dev/null 2>&1; then
    ok "ns1 can ping ns2 (10.0.0.2)"
else
    bad "ns1 cannot ping ns2 — check link state (ip link) and addressing (ip addr) inside both namespaces"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] Lab 1 is healthy."
    exit 0
else
    exit 1
fi
