#!/usr/bin/env bash
# Lab 9 — Process Stuck in D State — reset.sh
#
# A D-state process cannot be killed (that's the entire point of the lab)
# — the only way to make one exit is to remove whatever it's blocked on
# and let the syscall finish naturally. So reset order matters:
#   1. remove the iptables DROP rules on the NFS port (2049), in both
#      directions — this lets any in-flight write finally get a response
#   2. wait (with a timeout) for any D-state process on /mnt/nfslab to
#      actually exit on its own
#   3. clean up leftover test files from Challenge A
#   4. re-run setup.sh to rebuild the broken "before" state fresh
#
# Safe to run even if nothing is currently broken, and safe to run twice
# in a row (removing an already-absent iptables rule or D-state process is
# a no-op, not an error).
#
# Usage: sudo bash reset.sh
set -uo pipefail

echo "[reset] Lab 9 — Process Stuck in D State"

# --- Step 1: remove iptables DROP rules (may be duplicated if Challenge A
# added a second copy without removing the first) ---
echo "[reset] removing iptables DROP rules on tcp/2049 (both directions)..."
while sudo iptables -C OUTPUT -p tcp --dport 2049 -j DROP 2>/dev/null; do
    sudo iptables -D OUTPUT -p tcp --dport 2049 -j DROP 2>/dev/null || break
    echo "[reset]   removed one OUTPUT DROP rule"
done
while sudo iptables -C INPUT -p tcp --sport 2049 -j DROP 2>/dev/null; do
    sudo iptables -D INPUT -p tcp --sport 2049 -j DROP 2>/dev/null || break
    echo "[reset]   removed one INPUT DROP rule"
done

# --- Step 2: wait for any D-state process on nfslab to exit naturally ---
echo "[reset] waiting up to 30s for any D-state nfslab process to unblock and exit..."
WAITED=0
while [ "$WAITED" -lt 30 ]; do
    STILL_STUCK=$(ps -eo pid,stat,cmd 2>/dev/null | awk '$2 ~ /^D/ && $0 ~ /nfslab/')
    if [ -z "$STILL_STUCK" ]; then
        echo "[reset] no D-state nfslab processes remain (after ${WAITED}s)"
        break
    fi
    sleep 2
    WAITED=$((WAITED+2))
done
if [ "$WAITED" -ge 30 ]; then
    STILL_STUCK=$(ps -eo pid,stat,cmd 2>/dev/null | awk '$2 ~ /^D/ && $0 ~ /nfslab/')
    if [ -n "$STILL_STUCK" ]; then
        echo "[reset] WARNING: process(es) still in D state after 30s — the NFS block is removed,"
        echo "        so this should resolve shortly on its own, but a stuck kernel NFS client"
        echo "        can occasionally take longer. Not forcing anything further (kill -9 cannot"
        echo "        touch a D-state process anyway). Re-check with:"
        echo "        ps -eo pid,stat,cmd | awk '\$2 ~ /^D/'"
    fi
fi

# --- Step 3: clean up leftover Challenge A test files, if the mount is usable ---
if mountpoint -q /mnt/nfslab 2>/dev/null; then
    for f in testfile file1 file2 file3; do
        if [ -e "/mnt/nfslab/$f" ]; then
            sudo timeout 5 rm -f "/mnt/nfslab/$f" 2>/dev/null \
                && echo "[reset] removed leftover /mnt/nfslab/$f" \
                || echo "[reset] could not remove /mnt/nfslab/$f (mount may still be settling, skipping)"
        fi
    done
fi

# --- Step 4: re-run setup.sh to rebuild the broken state ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[reset] re-running setup.sh to rebuild the incident..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
