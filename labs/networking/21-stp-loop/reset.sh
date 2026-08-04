#!/usr/bin/env bash
set -uo pipefail

# Lab 21 - STP Loop: tear down and rebuild sw1/sw2/h1/h2 from scratch.
# No containerlab here - just namespaces, veths, and bridges - so reset
# is a clean re-run of setup.sh's teardown+build logic. This returns you
# to the STP-off "before" state, not the fixed state - replay the README
# from Step 4 onward to get back to healthy.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] tearing down existing namespaces and bridges..."
for ns in h1 h2; do
  sudo ip netns del "$ns" 2>/dev/null || true
done
for br in sw1 sw2; do
  sudo ip link del "$br" 2>/dev/null || true
done
echo "[reset] teardown complete"

echo "[reset] rebuilding topology via setup.sh..."
bash "$DIR/setup.sh"

echo "[reset] Lab 21 topology redeployed fresh (STP off - replay README Steps 4-8)"
