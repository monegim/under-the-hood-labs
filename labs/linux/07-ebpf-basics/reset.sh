#!/usr/bin/env bash
# Lab 7 — eBPF Basics — reset.sh
#
# This lab doesn't build any persistent kernel/filesystem state — every
# `bpftrace` invocation in the README is meant to be Ctrl-C'd manually.
# The only thing that can leak past a session is a bpftrace process left
# running in the background (e.g. if a terminal was closed instead of
# Ctrl-C'd). This kills any such lingering process.
#
# Safe to run even if none is running, and safe to run twice in a row.
#
# Usage: sudo bash reset.sh
set -uo pipefail

echo "[reset] Lab 7 — eBPF Basics"

PIDS=$(pgrep -x bpftrace 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    echo "[reset] killing lingering bpftrace process(es): $PIDS"
    # shellcheck disable=SC2086
    sudo kill -9 $PIDS 2>/dev/null || true
else
    echo "[reset] no lingering bpftrace process found, skipping"
fi

echo "[reset] done. Re-run README.md Steps 1-4 to try the lab again."
