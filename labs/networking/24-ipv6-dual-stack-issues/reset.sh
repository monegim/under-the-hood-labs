#!/usr/bin/env bash
set -uo pipefail

# Lab 24 - IPv6 Dual-Stack Issues: tear down and rebuild client/server from
# scratch (kills the background http.server processes too, and with them
# any ip6tables rules added during the lab, since the whole netns and its
# processes go away). No containerlab here - just namespaces, veths, and
# python processes - so reset is a clean re-run of setup.sh's teardown+
# build logic.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] tearing down existing namespaces and listeners..."
sudo pkill -f "http.server 80" 2>/dev/null || true
for ns in client server; do
  sudo ip netns del "$ns" 2>/dev/null || true
done
echo "[reset] teardown complete"

echo "[reset] rebuilding topology via setup.sh..."
bash "$DIR/setup.sh"

echo "[reset] Lab 24 topology redeployed fresh (both stacks healthy)"
