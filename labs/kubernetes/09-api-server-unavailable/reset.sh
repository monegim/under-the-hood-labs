#!/usr/bin/env bash
# Lab 9 — API Server Unavailable — reset.sh
#
# Deletes the "k8s09" kind cluster entirely (also undoes Challenge B's
# stopped container, since the whole cluster is removed) and re-runs
# setup.sh to rebuild the incident from scratch.
#
# Usage: bash reset.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] Lab 9 — API Server Unavailable"

# The control-plane container may be stopped (Challenge B) rather than
# just unhealthy - start it first so "kind delete cluster" can clean up
# normally instead of leaving orphaned stopped containers behind.
docker start k8s09-control-plane >/dev/null 2>&1 || true

if command -v kind >/dev/null && kind get clusters 2>/dev/null | grep -qx "k8s09"; then
    kind delete cluster --name k8s09
    echo "[reset] deleted kind cluster 'k8s09'"
else
    echo "[reset] kind cluster 'k8s09' not present, skipping"
fi

echo "[reset] re-running setup.sh to rebuild the incident..."
bash "${SCRIPT_DIR}/setup.sh"

echo "[reset] done."
