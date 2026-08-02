#!/usr/bin/env bash
# Lab 2 — PID + Mount Namespaces — reset.sh
#
# This lab doesn't build persistent kernel objects under normal use (the
# namespaces created by `unshare` die with the shell that created them).
# What CAN leak past the lab session:
#   - backgrounded `sleep 100` processes from Step 4 (and Challenge A's
#     `unshare --mount sleep 100 &`)
#   - the tmpfs mounted at $HOME-independent path /mnt/nsdemo in Step 3,
#     if the shell that created it was never exited cleanly
#   - the tmpfs mounted at /mnt in Challenge A, which (unlike Step 3) is
#     expected to leak onto the HOST if `/` has `shared` propagation —
#     that's the whole point of the challenge, so it needs explicit cleanup
#   - our own check.sh's test `sleep` process, if it was interrupted
#     mid-run and didn't reach its own cleanup step
#
# Safe to run even if none of this is present, and safe to run twice in a
# row.
#
# Usage: sudo bash reset.sh
set -uo pipefail

echo "[reset] Lab 2 — PID + Mount Namespaces"

# --- kill lingering background sleep/unshare test processes ---
for pat in "unshare --mount sleep 100" "unshare --pid --fork --mount --mount-proc sleep" "sleep 100"; do
    PIDS=$(pgrep -f "$pat" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        echo "[reset] killing lingering process(es) matching '$pat': $PIDS"
        # shellcheck disable=SC2086
        sudo kill -9 $PIDS 2>/dev/null || true
    fi
done

# --- unmount leftover tmpfs from Step 3 (/mnt/nsdemo) ---
if mountpoint -q /mnt/nsdemo 2>/dev/null; then
    sudo umount /mnt/nsdemo 2>/dev/null || true
    echo "[reset] unmounted /mnt/nsdemo"
else
    echo "[reset] /mnt/nsdemo not mounted, skipping"
fi

# --- unmount leftover tmpfs from Challenge A (/mnt) ---
if mountpoint -q /mnt 2>/dev/null; then
    sudo umount /mnt 2>/dev/null || true
    echo "[reset] unmounted /mnt"
else
    echo "[reset] /mnt not mounted, skipping"
fi

echo "[reset] done. Re-run README.md Steps 1-4 to build the lab again."
