#!/usr/bin/env bash
set -uo pipefail

# Lab 28 reset - tears down ns1/ns2, restores IPv6 (in case Challenge A
# disabled it globally on the host), and rebuilds via setup.sh.

for ns in ns1 ns2; do
  sudo ip netns del "$ns" 2>/dev/null || true
done

echo "[reset] restoring IPv6 on the host in case Challenge A disabled it..."
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
