#!/usr/bin/env bash
# Incident 10 reset - stops both services and re-runs setup.sh to
# rebuild the incident fresh (including resetting client-traffic's
# RETRIES back to the broken value of 3).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] stopping services..."
sudo systemctl stop client-traffic.service backend.service 2>/dev/null || true

echo "[reset] re-running setup.sh to recreate the incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
