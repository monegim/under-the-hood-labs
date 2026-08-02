#!/usr/bin/env bash
# Lab 4 — Build Your Own Container — reset.sh
#
# Tears down everything the lab (Steps 1-6) and its challenges create:
#   - kills the running container process(es) (chroot into $ROOTFS)
#   - removes the mycontainer and mycontainer2 (Challenge B) cgroups
#   - removes the rootfs directory built under $HOME/mycontainer
#
# Safe to run even if none of this exists, and safe to run twice in a row.
#
# Usage: sudo bash reset.sh — REAL_HOME resolution below makes sure $ROOTFS
# still points at the invoking user's directory, not /root's, even though
# the whole script runs under sudo (sudo resets $HOME by default).
set -uo pipefail

echo "[reset] Lab 4 — Build Your Own Container"

if [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
fi
REAL_HOME="${REAL_HOME:-$HOME}"

ROOTFS="$REAL_HOME/mycontainer/rootfs"

# --- kill any running container process(es) ---
PIDS=$(pgrep -f "chroot $ROOTFS" 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    echo "[reset] killing container process(es): $PIDS"
    # shellcheck disable=SC2086
    sudo kill -9 $PIDS 2>/dev/null || true
    sleep 0.3
else
    echo "[reset] no running container process found, skipping"
fi

# --- remove cgroups (mycontainer, mycontainer2 from Challenge B) ---
for cg in mycontainer mycontainer2; do
    DIR="/sys/fs/cgroup/$cg"
    if [ -d "$DIR" ]; then
        if [ -f "$DIR/cgroup.procs" ]; then
            CGPIDS=$(cat "$DIR/cgroup.procs" 2>/dev/null || true)
            if [ -n "$CGPIDS" ]; then
                # shellcheck disable=SC2086
                sudo kill -9 $CGPIDS 2>/dev/null || true
                sleep 0.2
            fi
        fi
        if sudo rmdir "$DIR" 2>/dev/null; then
            echo "[reset] removed $DIR"
        else
            echo "[reset] could not remove $DIR (still busy?)"
        fi
    else
        echo "[reset] $DIR not present, skipping"
    fi
done

# --- remove the rootfs/chroot directory ---
if [ -d "$REAL_HOME/mycontainer" ]; then
    rm -rf "$REAL_HOME/mycontainer"
    echo "[reset] removed $REAL_HOME/mycontainer"
else
    echo "[reset] $REAL_HOME/mycontainer not present, skipping"
fi

echo "[reset] done. Re-run README.md Steps 1-6 to build the lab again."
