#!/usr/bin/env bash
set -uo pipefail

# Lab 29 reset - tears down ns1/ns2/ns3 and br29, and rebuilds via
# setup.sh.

for ns in ns1 ns2 ns3; do
  sudo ip netns del "$ns" 2>/dev/null || true
done
sudo ip link del br29 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
