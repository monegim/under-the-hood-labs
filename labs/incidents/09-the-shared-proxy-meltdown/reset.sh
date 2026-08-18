#!/usr/bin/env bash
# Incident 09 reset - stops everything, kills any leftover hung
# requests from a previous run, and re-runs setup.sh to rebuild the
# incident fresh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] stopping services..."
sudo systemctl stop service-a.service service-b.service 2>/dev/null || true
sudo systemctl stop nginx 2>/dev/null || true

echo "[reset] killing any leftover hung curl requests from a previous run..."
pkill -f "curl.*127.0.0.1:8080/b/" 2>/dev/null || true

echo "[reset] re-running setup.sh to recreate the incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
