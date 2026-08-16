#!/usr/bin/env bash
# Lab 14 — PDB Blocking Drain — reset.sh
#
# Deletes the "k8s14" kind cluster entirely (cleanest way to undo any
# cordon/scale/PDB-patch state) and re-runs setup.sh to rebuild the
# incident from scratch.
#
# Usage: bash reset.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] Lab 14 — PDB Blocking Drain"

if command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx "k8s14"; then
    kind delete cluster --name k8s14
    echo "[reset] deleted kind cluster 'k8s14'"
else
    echo "[reset] kind cluster 'k8s14' not present, skipping"
fi

echo "[reset] re-running setup.sh to rebuild the incident..."
bash "${SCRIPT_DIR}/setup.sh"

echo "[reset] done."
