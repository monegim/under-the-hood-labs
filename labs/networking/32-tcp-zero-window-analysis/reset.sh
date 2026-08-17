#!/usr/bin/env bash
set -uo pipefail

# Lab 32 reset - tears down both namespaces and rebuilds via setup.sh.

for ns in client server; do
  sudo ip netns del "$ns" 2>/dev/null || true
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
