#!/usr/bin/env bash
# Lab 9 — Process Stuck in D State — check.sh
#
# Verifies the D-state incident setup.sh (and Challenge A) create is
# actually resolved:
#   - no process tied to the /mnt/nfslab mount is stuck in D state
#   - the iptables DROP rules on the NFS port (2049) that caused the hang
#     are gone (both directions)
#   - the NFS mount is actually responsive (not just "not currently
#     D-state" — a quick write against it should complete)
#
# Usage: sudo bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 9 — Process Stuck in D State"
echo

# --- no D-state process tied to the nfslab mount ---
DSTATE=$(ps -eo pid,stat,cmd 2>/dev/null | awk '$2 ~ /^D/ && $0 ~ /nfslab/')
if [ -z "$DSTATE" ]; then
    ok "no D-state process referencing /mnt/nfslab or its files"
else
    bad "found D-state process(es) still referencing nfslab:"
    echo "$DSTATE" | sed 's/^/       /'
fi

# --- also catch any D-state dd process in general (in case cmdline was truncated) ---
DSTATE_DD=$(ps -eo pid,stat,cmd 2>/dev/null | awk '$2 ~ /^D/ && $3 == "dd"')
if [ -z "$DSTATE_DD" ]; then
    ok "no D-state 'dd' process found"
else
    bad "found D-state 'dd' process(es):"
    echo "$DSTATE_DD" | sed 's/^/       /'
fi

# --- iptables DROP rules on NFS port (2049) removed, both directions ---
if sudo iptables -C OUTPUT -p tcp --dport 2049 -j DROP 2>/dev/null; then
    bad "OUTPUT DROP rule for tcp/2049 is still present — this is the actual root cause, remove it"
else
    ok "no OUTPUT DROP rule for tcp/2049"
fi

if sudo iptables -C INPUT -p tcp --sport 2049 -j DROP 2>/dev/null; then
    bad "INPUT DROP rule for tcp/2049 is still present — this is the actual root cause, remove it"
else
    ok "no INPUT DROP rule for tcp/2049"
fi

# --- mount is actually responsive, not just quiet ---
if mountpoint -q /mnt/nfslab 2>/dev/null; then
    if sudo timeout 3 touch /mnt/nfslab/.lab9_check_alive 2>/dev/null; then
        ok "/mnt/nfslab is mounted and responds to a quick write within 3s"
        sudo rm -f /mnt/nfslab/.lab9_check_alive 2>/dev/null || true
    else
        bad "/mnt/nfslab is mounted but did not respond to a write within 3s — mount may still be hung"
    fi
else
    ok "/mnt/nfslab is not currently mounted (nothing to check — run setup.sh to build the lab)"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] No stuck D-state processes; NFS path is clear."
    exit 0
else
    exit 1
fi
