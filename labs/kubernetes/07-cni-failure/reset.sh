#!/usr/bin/env bash
# Lab 7 — CNI Failure — reset.sh
#
# Deletes the "k8s07" kind cluster entirely (also undoes any renamed CNI
# config file from Challenge B, since the whole node container is
# removed) and re-runs setup.sh to rebuild the incident from scratch.
#
# Usage: bash reset.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] Lab 7 — CNI Failure"

if command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx "k8s07"; then
    kind delete cluster --name k8s07
    echo "[reset] deleted kind cluster 'k8s07'"
else
    echo "[reset] kind cluster 'k8s07' not present, skipping"
fi

echo "[reset] re-running setup.sh to rebuild the incident..."
bash "${SCRIPT_DIR}/setup.sh"

echo "[reset] done."
