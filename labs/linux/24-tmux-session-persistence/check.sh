#!/usr/bin/env bash
# Lab 24 check — runs its own short throwaway job inside a fresh
# detached tmux session and verifies it runs to completion untouched.
# This validates the actual mechanism (tmux session persistence) that
# the whole lab is about, independent of whichever demo path the
# learner walked through manually.
set -uo pipefail

if ! command -v tmux >/dev/null 2>&1; then
    echo "[FAIL] tmux is not installed — run setup.sh first."
    exit 1
fi

MARKER=/var/tmp/lab24/check-done
rm -f "$MARKER"

echo "[check] starting a short job inside a fresh detached tmux session..."
tmux kill-session -t lab24check 2>/dev/null || true
tmux new-session -d -s lab24check "sleep 5 && echo done > $MARKER"

echo "[check] confirming the session exists and is genuinely detached..."
if ! tmux has-session -t lab24check 2>/dev/null; then
    echo "[FAIL] tmux session never came up."
    exit 1
fi

echo "[check] waiting for the job to finish (it has no idea whether anyone is attached)..."
for i in $(seq 1 15); do
    [ -f "$MARKER" ] && break
    sleep 1
done

tmux kill-session -t lab24check 2>/dev/null || true

if [ -f "$MARKER" ]; then
    echo "[PASS] job inside the detached tmux session ran to completion."
    rm -f "$MARKER"
    exit 0
else
    echo "[FAIL] job never completed — tmux session persistence isn't working as expected on this system."
    exit 1
fi
