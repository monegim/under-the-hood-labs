#!/usr/bin/env bash
# Lab 3 — cgroups (v2) — check.sh
#
# Verifies the mechanism Steps 1-3 of README.md build:
#   - cgroup v2 (unified hierarchy) is actually mounted
#   - a test cgroup can be created under /sys/fs/cgroup
#   - memory.max / cpu.max can be set and read back correctly
#   - a process placed in a low-memory-limited cgroup actually gets
#     OOM-killed by the CGROUP's own OOM killer (memory.events' oom_kill
#     counter), not just "the limit file has a number in it"
#
# Builds its own throwaway cgroup (lab3_check) to do the live enforcement
# test, and removes it when done — it does not touch lab3/lab3b/lab3c from
# the README/challenges (see reset.sh for that).
#
# Usage: sudo bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 3 — cgroups (v2)"
echo

# --- cgroup v2 mounted ---
FSTYPE=$(stat -fc %T /sys/fs/cgroup 2>/dev/null || true)
if [ "$FSTYPE" = "cgroup2fs" ]; then
    ok "cgroup v2 (cgroup2fs) is mounted at /sys/fs/cgroup"
else
    bad "cgroup v2 does not appear to be mounted (stat -fc %T /sys/fs/cgroup = '$FSTYPE'); this system may be in hybrid v1+v2 mode"
    echo
    echo "[check] $PASS passed, $FAIL failed"
    exit 1
fi

CGDIR=/sys/fs/cgroup/lab3_check

cleanup() {
    if [ -d "$CGDIR" ]; then
        for pid in $(cat "$CGDIR/cgroup.procs" 2>/dev/null || true); do
            sudo kill -9 "$pid" 2>/dev/null || true
        done
        sleep 0.2
        sudo rmdir "$CGDIR" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# --- create test cgroup ---
if sudo mkdir -p "$CGDIR" 2>/dev/null; then
    ok "created test cgroup $CGDIR"
else
    bad "could not create $CGDIR"
    exit 1
fi

# --- delegate controllers from root (idempotent: fine if already enabled) ---
echo "+memory +cpu +pids" | sudo tee /sys/fs/cgroup/cgroup.subtree_control >/dev/null 2>&1 || true

if [ -f "$CGDIR/memory.max" ] && [ -f "$CGDIR/cpu.max" ]; then
    ok "memory.max and cpu.max exist (controllers delegated correctly)"
else
    bad "memory.max/cpu.max missing under $CGDIR — controllers not delegated via cgroup.subtree_control"
    exit 1
fi

# --- memory.max set + read back ---
LIMIT_BYTES=$((20*1024*1024))
echo "$LIMIT_BYTES" | sudo tee "$CGDIR/memory.max" >/dev/null 2>&1
READBACK=$(cat "$CGDIR/memory.max" 2>/dev/null || true)
if [ "$READBACK" = "$LIMIT_BYTES" ]; then
    ok "memory.max set to $LIMIT_BYTES and read back correctly"
else
    bad "memory.max readback mismatch (wrote $LIMIT_BYTES, read '$READBACK')"
fi

# --- cpu.max set + read back ---
echo "50000 100000" | sudo tee "$CGDIR/cpu.max" >/dev/null 2>&1
CPU_READBACK=$(cat "$CGDIR/cpu.max" 2>/dev/null || true)
if [ "$CPU_READBACK" = "50000 100000" ]; then
    ok "cpu.max set to '50000 100000' and read back correctly"
else
    bad "cpu.max readback mismatch (wrote '50000 100000', read '$CPU_READBACK')"
fi

# --- live enforcement test: a process over the memory limit gets OOM-killed ---
# Sleeps briefly before allocating so we have a window to add its PID to
# cgroup.procs before it tries to exceed the limit.
python3 -c "
import time
time.sleep(1)
data = bytearray(120 * 1024 * 1024)  # 120MB, well over the 20MB cap
time.sleep(5)
" >/dev/null 2>&1 &
TESTPID=$!

sleep 0.3
if echo "$TESTPID" | sudo tee "$CGDIR/cgroup.procs" >/dev/null 2>&1; then
    ok "joined test process (PID $TESTPID) to $CGDIR"
else
    bad "could not add test process to cgroup.procs"
fi

# Wait for the process to either get OOM-killed or finish/timeout.
wait "$TESTPID" 2>/dev/null
OOM_COUNT=$(grep '^oom_kill' "$CGDIR/memory.events" 2>/dev/null | awk '{print $2}')
STILL_MEMBER=$(cat "$CGDIR/cgroup.procs" 2>/dev/null || true)

if [ -n "${OOM_COUNT:-}" ] && [ "$OOM_COUNT" -gt 0 ]; then
    ok "cgroup OOM killer fired (memory.events oom_kill=$OOM_COUNT) — 20MB limit enforced against a 120MB allocation"
else
    bad "no oom_kill recorded in memory.events (oom_kill=${OOM_COUNT:-0}) — memory limit was not enforced"
fi

if [ -z "$STILL_MEMBER" ]; then
    ok "test process no longer present in cgroup.procs (it was reaped)"
else
    bad "test process(es) still listed in cgroup.procs: $STILL_MEMBER"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] cgroup v2 memory/cpu enforcement works on this box."
    exit 0
else
    exit 1
fi
