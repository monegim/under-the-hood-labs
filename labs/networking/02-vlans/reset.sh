#!/usr/bin/env bash
set -uo pipefail

# Lab 2 - VLANs: tear down and rebuild br0 + ns1-4 + router from scratch.
# No containerlab here - just namespaces, veths, and a VLAN-filtering
# bridge - so reset is a clean re-run of setup.sh's teardown+build logic.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] tearing down existing namespaces and bridge..."
for ns in ns1 ns2 ns3 ns4 router; do
  sudo ip netns del "$ns" 2>/dev/null || true
done
sudo ip link del br0 2>/dev/null || true
echo "[reset] teardown complete"

echo "[reset] rebuilding topology via setup.sh..."
bash "$DIR/setup.sh"

echo "[reset] Lab 2 topology redeployed fresh"
