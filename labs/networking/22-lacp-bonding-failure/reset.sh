#!/usr/bin/env bash
set -uo pipefail

# Lab 22 - LACP Bonding Failure: tear down and rebuild h1/h2/bond0 from
# scratch (also removes h3, used only in Challenge B). No containerlab
# here - just namespaces, veths, and bonds - so reset is a clean re-run
# of setup.sh's teardown+build logic.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] tearing down existing namespaces..."
for ns in h1 h2 h3; do
  sudo ip netns del "$ns" 2>/dev/null || true
done
echo "[reset] teardown complete"

echo "[reset] rebuilding topology via setup.sh..."
bash "$DIR/setup.sh"

echo "[reset] Lab 22 topology redeployed fresh (healthy 2-port aggregate)"
