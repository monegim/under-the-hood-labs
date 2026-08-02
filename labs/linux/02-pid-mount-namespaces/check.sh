#!/usr/bin/env bash
# Lab 2 — PID + Mount Namespaces — check.sh
#
# This lab is exploratory/observational (Steps 1-4 are about watching `ps
# aux` and `findmnt` output change, not about leaving a persistent object
# behind). There's no single "end state" to inspect after the fact, so
# instead this check builds its own short-lived PID+mount namespace (the
# "done right" combination from Step 1: `unshare --pid --fork --mount
# --mount-proc`), and proves the underlying MECHANISM actually works on
# this box:
#   - the namespaced process has a different PID inside vs outside
#     (via /proc/<pid>/status' NSpid field when the kernel exposes it,
#     falling back to nsenter + ps showing PID 1 on older kernels)
# It cleans up the test process itself when done.
#
# Usage: sudo bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 2 — PID + Mount Namespaces"
echo

# --- prerequisite tools ---
if command -v unshare >/dev/null && command -v nsenter >/dev/null; then
    ok "unshare and nsenter are available"
else
    bad "unshare/nsenter not found (util-linux missing?)"
    echo
    echo "[check] $PASS passed, $FAIL failed"
    exit 1
fi

# --- spin up a test PID+mount namespace running a uniquely-identifiable sleep ---
MARKER_SECS=63771
sudo unshare --pid --fork --mount --mount-proc "sleep" "$MARKER_SECS" &
UNSHARE_JOB_PID=$!

# Give the namespace a moment to be set up and the child to exec.
sleep 0.5

# Find the REAL (host-visible) PID of the sleep process we just started.
# It is a child of the unshare process we backgrounded.
HOST_SLEEP_PID=$(pgrep -f "sleep $MARKER_SECS" | head -n1)

if [ -z "${HOST_SLEEP_PID:-}" ]; then
    bad "could not find the test 'sleep $MARKER_SECS' process on the host — unshare may have failed"
    kill "$UNSHARE_JOB_PID" 2>/dev/null || true
    echo
    echo "[check] $PASS passed, $FAIL failed"
    exit 1
fi
ok "test namespace created, host PID is $HOST_SLEEP_PID"

# --- prove PID isolation: inside vs outside PID differ ---
CHECKED_VIA=""
if [ -r "/proc/$HOST_SLEEP_PID/status" ] && grep -q '^NSpid:' "/proc/$HOST_SLEEP_PID/status" 2>/dev/null; then
    NSPID_LINE=$(grep '^NSpid:' "/proc/$HOST_SLEEP_PID/status")
    INNER_PID=$(echo "$NSPID_LINE" | awk '{print $NF}')
    OUTER_PID=$(echo "$NSPID_LINE" | awk '{print $2}')
    CHECKED_VIA="NSpid field ($NSPID_LINE)"
    if [ "$INNER_PID" = "1" ] && [ "$OUTER_PID" = "$HOST_SLEEP_PID" ]; then
        ok "process has host PID $OUTER_PID but is PID $INNER_PID inside its own namespace ($CHECKED_VIA)"
    else
        bad "NSpid did not show the expected host-vs-namespace PID split ($CHECKED_VIA)"
    fi
else
    # Fallback for kernels without NSpid (pre-4.1): nsenter into the pid+mount
    # namespace and read the namespace's own view via ps.
    INNER_PS=$(sudo nsenter -t "$HOST_SLEEP_PID" --mount --pid ps aux 2>/dev/null)
    CHECKED_VIA="nsenter + ps (no NSpid field on this kernel)"
    if echo "$INNER_PS" | awk '{print $2}' | grep -qx 1; then
        ok "namespace's own ps shows PID 1 present ($CHECKED_VIA)"
    else
        bad "could not confirm PID 1 from inside the namespace ($CHECKED_VIA)"
    fi
fi

# --- cleanup our test process ---
sudo kill "$HOST_SLEEP_PID" 2>/dev/null || true
wait "$UNSHARE_JOB_PID" 2>/dev/null || true

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] PID+mount namespace mechanism works on this box."
    exit 0
else
    exit 1
fi
