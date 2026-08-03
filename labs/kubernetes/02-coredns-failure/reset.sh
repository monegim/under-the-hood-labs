#!/usr/bin/env bash
# Lab 2 — CoreDNS Failure — reset.sh
#
# Deletes the "k8s02" kind cluster entirely and re-runs setup.sh to rebuild
# the incident from scratch.
#
# Usage: bash reset.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] Lab 2 — CoreDNS Failure"

if command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx "k8s02"; then
    kind delete cluster --name k8s02
    echo "[reset] deleted kind cluster 'k8s02'"
else
    echo "[reset] kind cluster 'k8s02' not present, skipping"
fi

echo "[reset] re-running setup.sh to rebuild the incident..."
bash "${SCRIPT_DIR}/setup.sh"

echo "[reset] done."
