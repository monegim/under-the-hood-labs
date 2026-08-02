#!/usr/bin/env bash
# Lab 6 — Kubernetes Internals — reset.sh
#
# Deletes the "lab6" kind cluster so the learner can recreate it cleanly
# (this also removes the nginx pod/service and any iptables/network state
# the challenges modified inside it — the whole node container goes away).
#
# Safe to run even if the cluster doesn't exist, and safe to run twice in
# a row.
#
# Usage: bash reset.sh
set -uo pipefail

echo "[reset] Lab 6 — Kubernetes Internals"

if ! command -v kind >/dev/null; then
    echo "[reset] kind not found in PATH — nothing to do"
    exit 0
fi

if kind get clusters 2>/dev/null | grep -qx "lab6"; then
    kind delete cluster --name lab6
    echo "[reset] deleted kind cluster 'lab6'"
else
    echo "[reset] kind cluster 'lab6' not present, skipping"
fi

echo "[reset] done. Re-run README.md Steps 1-4 to build the lab again."
