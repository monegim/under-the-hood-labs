#!/usr/bin/env bash
# Lab 20 check — is there a healthy zombie_parent running, and does it
# currently have zero zombie (Z-state) children? A trivial "nothing is
# running at all" does NOT count as a pass - that's not fixed, that's gone.
set -uo pipefail

PASS=0
PARENT_PIDS=""

echo "[check] looking for a running zombie_parent process..."
if pgrep -f zombie_parent > /dev/null 2>&1; then
    PARENT_PIDS=$(pgrep -f zombie_parent)
    echo "[check] found zombie_parent process(es): $PARENT_PIDS"
else
    echo "[FAIL] no zombie_parent process is running at all - the lab isn't in a resolved state, it's just gone."
    PASS=1
fi

echo "[check] counting zombie (Z-state) processes under any zombie_parent PID..."
ZOMBIE_COUNT=0
for PPID in $PARENT_PIDS; do
    COUNT=$(ps -eo pid,ppid,stat --no-headers | awk -v ppid="$PPID" '$2 == ppid && $3 ~ /^Z/' | wc -l)
    echo "[check] zombies under PPID $PPID: $COUNT"
    ZOMBIE_COUNT=$((ZOMBIE_COUNT + COUNT))
done

if [ "$ZOMBIE_COUNT" -gt 0 ]; then
    echo "[FAIL] $ZOMBIE_COUNT zombie(s) still present under a zombie_parent process."
    ps -eo pid,ppid,stat,cmd | awk '$3 ~ /^Z/'
    PASS=1
else
    echo "[check] zero zombies found under tracked parent(s)."
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] a healthy zombie_parent is running and it has zero unreaped children."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
