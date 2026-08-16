#!/usr/bin/env bash
# Lab 18 — Kubelet Client Certificate Rotation Failure — reset.sh
#
# Deletes the "k8s18" kind cluster entirely (also undoes the replaced
# kubelet cert, since the whole node container is removed) and re-runs
# setup.sh to rebuild the incident from scratch.
#
# Usage: bash reset.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] Lab 18 — Kubelet Client Certificate Rotation Failure"

if command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx "k8s18"; then
    kind delete cluster --name k8s18
    echo "[reset] deleted kind cluster 'k8s18'"
else
    echo "[reset] kind cluster 'k8s18' not present, skipping"
fi

echo "[reset] re-running setup.sh to rebuild the incident..."
bash "${SCRIPT_DIR}/setup.sh"

echo "[reset] done."
