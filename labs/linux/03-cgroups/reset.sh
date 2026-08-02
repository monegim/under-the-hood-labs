#!/usr/bin/env bash
# Lab 3 — cgroups (v2) — reset.sh
#
# Removes every cgroup this lab (and its challenges, and check.sh) can
# create: lab3 (main lab), lab3b (Challenge A), lab3c (Challenge B), and
# lab3_check (check.sh's own throwaway test cgroup). A cgroup directory
# can't be rmdir'd while it still has member processes, so this first
# kills anything still listed in each cgroup's cgroup.procs, then removes
# the directory.
#
# Safe to run even if none of these exist, and safe to run twice in a row.
#
# Usage: sudo bash reset.sh
set -uo pipefail

echo "[reset] Lab 3 — cgroups (v2)"

for cg in lab3 lab3b lab3c lab3_check; do
    DIR="/sys/fs/cgroup/$cg"
    if [ -d "$DIR" ]; then
        if [ -f "$DIR/cgroup.procs" ]; then
            PIDS=$(cat "$DIR/cgroup.procs" 2>/dev/null || true)
            if [ -n "$PIDS" ]; then
                echo "[reset] killing process(es) still in $cg: $PIDS"
                # shellcheck disable=SC2086
                sudo kill -9 $PIDS 2>/dev/null || true
                sleep 0.3
            fi
        fi
        if sudo rmdir "$DIR" 2>/dev/null; then
            echo "[reset] removed $DIR"
        else
            echo "[reset] could not remove $DIR (still busy?) — check for remaining member processes"
        fi
    else
        echo "[reset] $DIR not present, skipping"
    fi
done

# Leftover stress-ng / test processes from this lab's steps and challenges.
for pat in "stress-ng" "bytearray(120"; do
    PIDS=$(pgrep -f "$pat" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        echo "[reset] killing lingering process(es) matching '$pat': $PIDS"
        # shellcheck disable=SC2086
        sudo kill -9 $PIDS 2>/dev/null || true
    fi
done

echo "[reset] done. Re-run README.md Steps 1-3 to build the lab again."
