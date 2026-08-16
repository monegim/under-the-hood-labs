#!/usr/bin/env bash
# Lab 16 — Probe Misconfiguration — reset.sh
#
# Deletes the "k8s16" kind cluster entirely and re-runs setup.sh to
# rebuild the incident from scratch.
#
# Usage: bash reset.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] Lab 16 — Probe Misconfiguration"

if command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx "k8s16"; then
    kind delete cluster --name k8s16
    echo "[reset] deleted kind cluster 'k8s16'"
else
    echo "[reset] kind cluster 'k8s16' not present, skipping"
fi

echo "[reset] re-running setup.sh to rebuild the incident..."
bash "${SCRIPT_DIR}/setup.sh"

echo "[reset] done."
