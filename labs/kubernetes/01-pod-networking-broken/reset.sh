#!/usr/bin/env bash
# Lab 1 — Pod Networking Broken — reset.sh
#
# Deletes the "k8s01" kind cluster entirely (cleanest way to undo Calico
# install + NetworkPolicy state) and re-runs setup.sh to rebuild the
# incident from scratch.
#
# Usage: bash reset.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] Lab 1 — Pod Networking Broken"

if command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx "k8s01"; then
    kind delete cluster --name k8s01
    echo "[reset] deleted kind cluster 'k8s01'"
else
    echo "[reset] kind cluster 'k8s01' not present, skipping"
fi

echo "[reset] re-running setup.sh to rebuild the incident..."
bash "${SCRIPT_DIR}/setup.sh"

echo "[reset] done."
