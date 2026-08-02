#!/usr/bin/env bash
# Lab 5 — Overlay Filesystems — reset.sh
#
# Unmounts the overlay and removes the lower/upper/work/merged/lower2
# directories built under $HOME/ovl (Steps 1, 2, 6), plus Challenge A's
# separate tmpfs mount and directory under /tmp/ovltest.
#
# Safe to run even if none of this exists, and safe to run twice in a row.
#
# Usage: sudo bash reset.sh
set -uo pipefail

echo "[reset] Lab 5 — Overlay Filesystems"

OVL="$HOME/ovl"

# --- unmount the overlay ---
if mountpoint -q "$OVL/merged" 2>/dev/null; then
    sudo umount "$OVL/merged" 2>/dev/null || true
    echo "[reset] unmounted $OVL/merged"
else
    echo "[reset] $OVL/merged not mounted, skipping"
fi

# --- remove the lab's directories ---
if [ -d "$OVL" ]; then
    rm -rf "$OVL"
    echo "[reset] removed $OVL"
else
    echo "[reset] $OVL not present, skipping"
fi

# --- Challenge A leftovers: /tmp/ovltest (tmpfs mount + dir) ---
if mountpoint -q /tmp/ovltest 2>/dev/null; then
    sudo umount /tmp/ovltest 2>/dev/null || true
    echo "[reset] unmounted /tmp/ovltest"
else
    echo "[reset] /tmp/ovltest not mounted, skipping"
fi

if [ -d /tmp/ovltest ]; then
    sudo rm -rf /tmp/ovltest
    echo "[reset] removed /tmp/ovltest"
else
    echo "[reset] /tmp/ovltest not present, skipping"
fi

echo "[reset] done. Re-run README.md Steps 1-6 to build the lab again."
