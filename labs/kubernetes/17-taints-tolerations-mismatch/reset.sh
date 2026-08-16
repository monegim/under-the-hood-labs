#!/usr/bin/env bash
# Lab 17 — Taints/Tolerations Mismatch — reset.sh
#
# Deletes the "k8s17" kind cluster entirely (also undoes any taint
# changes, since the whole node container is removed) and re-runs
# setup.sh to rebuild the incident from scratch.
#
# Usage: bash reset.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] Lab 17 — Taints/Tolerations Mismatch"

if command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx "k8s17"; then
    kind delete cluster --name k8s17
    echo "[reset] deleted kind cluster 'k8s17'"
else
    echo "[reset] kind cluster 'k8s17' not present, skipping"
fi

echo "[reset] re-running setup.sh to rebuild the incident..."
bash "${SCRIPT_DIR}/setup.sh"

echo "[reset] done."
