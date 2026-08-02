#!/usr/bin/env bash
# Lab 8 — Why Is the Server Slow — check.sh
#
# Verifies the CPU/memory pressure setup.sh (and the challenges) create is
# actually gone:
#   - no report-generator.sh / disguised `yes` hog process (main lab)
#   - no leftover pile of bare `yes` processes (Challenge A)
#   - no leftover Python memory-leak hog (Challenge B)
# Also prints current load average vs nproc and free memory as context —
# load average is a trailing average, so it can take up to a minute after
# the hogs are killed to fully settle; that's informational only and does
# not by itself fail the check.
#
# Usage: bash check.sh
set -uo pipefail

PASS=0
FAIL=0

ok()   { echo "[PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "[check] Lab 8 — Why Is the Server Slow"
echo

# --- main lab hog: report-generator.sh (wraps `yes > /dev/null`) ---
RG_PIDS=$(pgrep -f 'report-generator.sh' 2>/dev/null || true)
if [ -z "$RG_PIDS" ]; then
    ok "no report-generator.sh process running"
else
    bad "report-generator.sh still running (PID(s): $RG_PIDS) — try: sudo pkill -f report-generator.sh"
fi

# --- Challenge A: bare `yes` processes (not necessarily via report-generator.sh) ---
YES_PIDS=$(pgrep -x 'yes' 2>/dev/null || true)
if [ -z "$YES_PIDS" ]; then
    ok "no bare 'yes' hog processes running"
else
    COUNT=$(echo "$YES_PIDS" | wc -l | tr -d ' ')
    bad "$COUNT 'yes' process(es) still running (PID(s): $YES_PIDS) — try: sudo pkill -x yes"
fi

# --- Challenge B: python memory-leak hog ---
PY_PIDS=$(pgrep -f 'hogs.append' 2>/dev/null || true)
if [ -z "$PY_PIDS" ]; then
    ok "no leftover Python memory-hog process running"
else
    bad "Python memory-hog still running (PID(s): $PY_PIDS) — try: pkill -f 'hogs.append'"
fi

# --- informational: load average vs core count, and free memory ---
echo
echo "[check] context (informational, does not affect pass/fail):"
NPROC=$(nproc 2>/dev/null || echo "?")
LOAD1=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo "?")
echo "  load average (1min): $LOAD1   cores (nproc): $NPROC"
echo "  (load average lags — allow up to a minute after killing hogs for it to settle)"
free -h 2>/dev/null | sed 's/^/  /' || true

echo
echo "[check] $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo "[check] No lab hog processes remain."
    exit 0
else
    exit 1
fi
