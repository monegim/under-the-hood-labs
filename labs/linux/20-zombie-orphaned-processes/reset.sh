#!/usr/bin/env bash
# Lab 20 reset — kill every process this lab may have started (buggy
# parent, fixed parent, extra Challenge A parents, Challenge B orphan
# demo), clean up state, then re-run setup.sh to reproduce the incident.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="/var/tmp/zombielab"

echo "[reset] killing any zombie_parent processes (buggy or fixed)..."
pkill -9 -f zombie_parent 2>/dev/null || true

echo "[reset] killing any leftover orphan-demo sleep processes from Challenge B..."
if [ -f "$WORKDIR/orphan.pid" ]; then
    kill -9 "$(cat "$WORKDIR/orphan.pid")" 2>/dev/null || true
fi

echo "[reset] cleaning up lab state..."
rm -rf "$WORKDIR"

echo "[reset] re-running setup.sh to rebuild the zombie-accumulation incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
