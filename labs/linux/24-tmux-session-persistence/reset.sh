#!/usr/bin/env bash
# Lab 24 reset — kills any leftover tmux sessions from previous attempts
# and any stray job.sh processes, then rebuilds via setup.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] killing any leftover lab tmux sessions..."
for s in labjob labjob2 toolate lab24check; do
    tmux kill-session -t "$s" 2>/dev/null || true
done

echo "[reset] killing any stray job.sh processes..."
pkill -f "/var/tmp/lab24/job.sh" 2>/dev/null || true

echo "[reset] rebuilding via setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
