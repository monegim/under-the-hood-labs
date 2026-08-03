#!/usr/bin/env bash
# Incident 02 reset - destroys the topology completely and rebuilds it
# via setup.sh, so the incident (including the ICMP-dropping iptables
# rule on r1) is freshly reproduced.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[reset] destroying existing topology (if any)..."
sudo containerlab destroy -t topology.clab.yml --cleanup 2>/dev/null || true

echo "[reset] re-running setup.sh to recreate the incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
