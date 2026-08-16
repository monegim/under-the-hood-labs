#!/usr/bin/env bash
# Lab 13 — StatefulSet PVC Mismatch — reset.sh
#
# Deletes the "k8s13" kind cluster entirely (cleanest way to undo any
# scale-down/scale-up/PVC-deletion state) and re-runs setup.sh to rebuild
# the lab from scratch.
#
# Usage: bash reset.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] Lab 13 — StatefulSet PVC Mismatch"

if command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx "k8s13"; then
    kind delete cluster --name k8s13
    echo "[reset] deleted kind cluster 'k8s13'"
else
    echo "[reset] kind cluster 'k8s13' not present, skipping"
fi

echo "[reset] re-running setup.sh to rebuild the lab..."
bash "${SCRIPT_DIR}/setup.sh"

echo "[reset] done."
