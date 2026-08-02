#!/usr/bin/env bash
# Lab 1 — Network Namespaces — reset.sh
#
# Tears down ns1 and ns2. Deleting a namespace automatically removes any
# interfaces (veth ends, etc.) that live inside it, so no separate veth
# cleanup is needed. Safe to run even if the namespaces don't exist, and
# safe to run more than once in a row.
#
# Usage: sudo bash reset.sh
set -uo pipefail

echo "[reset] Lab 1 — Network Namespaces"

for ns in ns1 ns2; do
    if ip netns list 2>/dev/null | grep -qw "$ns"; then
        sudo ip netns del "$ns" 2>/dev/null || true
        echo "[reset] deleted namespace $ns"
    else
        echo "[reset] namespace $ns not present, skipping"
    fi
done

echo "[reset] done. Re-run README.md Steps 1-4 to build the lab again."
