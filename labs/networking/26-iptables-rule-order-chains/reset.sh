#!/usr/bin/env bash
set -uo pipefail

# Lab 26 reset - tears down ns1/ns2 and rebuilds via setup.sh.

for ns in ns1 ns2; do
  sudo ip netns del "$ns" 2>/dev/null || true
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
