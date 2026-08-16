#!/usr/bin/env bash
# Incident 06 reset — deletes the kind cluster entirely and rebuilds it
# from scratch via setup.sh (v1 deployed and proven healthy, then rolled
# forward to the broken v2, exactly like the original page).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER="incident06"

echo "[reset] deleting the '${CLUSTER}' kind cluster..."
kind delete cluster --name "${CLUSTER}" >/dev/null 2>&1 || true

echo "[reset] rebuilding via setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
