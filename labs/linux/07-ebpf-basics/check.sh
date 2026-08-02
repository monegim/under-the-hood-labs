#!/usr/bin/env bash
# Lab 7 — eBPF Basics — check.sh
#
# eBPF traces are inherently transient (Steps 2-4 are "run a one-liner,
# watch live output, Ctrl-C"), so there's no persistent end state to
# inspect after the fact. Instead this check proves the MECHANISM itself
# works on this box:
#   - bpftrace is installed
#   - a basic tracepoint probe (the same one Step 2 uses,
#     tracepoint:syscalls:sys_enter_execve) actually attaches and fires
#     when a process execs
# It triggers the event itself (running /bin/true) and confirms the probe
# captured it, then cleans up its own background bpftrace process.
#
# Usage: sudo bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 7 — eBPF Basics"
echo

if ! command -v bpftrace >/dev/null; then
    bad "bpftrace is not installed"
    echo
    echo "[check] $PASS passed, $FAIL failed"
    exit 1
fi
ok "bpftrace is installed ($(bpftrace --version 2>/dev/null | head -n1))"

OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

# Run a short-lived probe on the exact tracepoint Step 2 uses, capped with
# `timeout` so it can never linger even if something goes wrong.
sudo timeout 6 bpftrace -e 'tracepoint:syscalls:sys_enter_execve { printf("EXECVE %s\n", comm); }' > "$OUT" 2>/dev/null &
BT_PID=$!

# Give bpftrace a moment to actually attach the probe before we trigger anything.
sleep 1.5

# Trigger a real execve event: /bin/true is a distinct, cheap binary to exec.
/bin/true

sleep 1

wait "$BT_PID" 2>/dev/null || true

if grep -q "EXECVE true" "$OUT" 2>/dev/null; then
    ok "probe fired: captured the execve of /bin/true"
else
    bad "probe did not capture the expected execve event (output: '$(cat "$OUT" 2>/dev/null)')"
fi

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] bpftrace tracing mechanism works on this box."
    exit 0
else
    exit 1
fi
