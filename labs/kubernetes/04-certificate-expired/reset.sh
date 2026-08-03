#!/usr/bin/env bash
# Lab 4 — Expired Certificate — reset.sh
#
# Deletes the "k8s04" kind cluster and any generated cert material under
# /tmp, then re-runs setup.sh to rebuild the incident from scratch.
#
# Usage: bash reset.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] Lab 4 — Expired Certificate"

if command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx "k8s04"; then
    kind delete cluster --name k8s04
    echo "[reset] deleted kind cluster 'k8s04'"
else
    echo "[reset] kind cluster 'k8s04' not present, skipping"
fi

rm -rf /tmp/lab4-certs /tmp/lab4-certs2 /tmp/lab4-rotate /tmp/lab4-rotate-a /tmp/lab4-webhook.py
echo "[reset] cleaned up /tmp cert material"

echo "[reset] re-running setup.sh to rebuild the incident..."
bash "${SCRIPT_DIR}/setup.sh"

echo "[reset] done."
