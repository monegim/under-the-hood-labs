#!/usr/bin/env bash
# Lab 6 — Node Under Memory Pressure — reset.sh
#
# Deletes the "k8s06" kind cluster (also cleans up any leftover
# /var/lib/lab6-fill from Challenge B, since the whole node container is
# removed) and re-runs setup.sh to rebuild the incident from scratch.
#
# Usage: bash reset.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] Lab 6 — Node Under Memory Pressure"

if command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx "k8s06"; then
    kind delete cluster --name k8s06
    echo "[reset] deleted kind cluster 'k8s06'"
else
    echo "[reset] kind cluster 'k8s06' not present, skipping"
fi

echo "[reset] re-running setup.sh to rebuild the incident..."
bash "${SCRIPT_DIR}/setup.sh"

echo "[reset] done."
