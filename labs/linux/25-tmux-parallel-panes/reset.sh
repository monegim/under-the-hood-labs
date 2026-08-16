#!/usr/bin/env bash
# Lab 25 reset — rebuilds the three simulated hosts from scratch.
# Doesn't touch any tmux session itself (this lab is done in whatever
# session you're already in) — just the underlying file state.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] rebuilding via setup.sh..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done. Your tmux panes/session are untouched — just re-cd into"
echo "        /var/tmp/lab25/hostN if you're reusing the same panes."
