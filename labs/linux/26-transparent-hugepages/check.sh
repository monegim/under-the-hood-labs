#!/usr/bin/env bash
# Lab 26 check — verifies THP is set to 'madvise' (not 'always'), and
# that the ordinary (non-opted-in) workload genuinely does NOT get
# backed by huge pages under that setting.
set -uo pipefail

THP_PATH="/sys/kernel/mm/transparent_hugepage/enabled"
WORKDIR="/var/tmp/lab26"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying THP is set to 'madvise'..."
CURRENT=$(grep -oP '(?<=\[)[a-z]+(?=\])' "$THP_PATH")
echo "[check] current setting: $CURRENT"
[ "$CURRENT" = "madvise" ] || fail "THP is set to '$CURRENT', expected 'madvise'"

echo "[check] confirming the ordinary workload does NOT trigger THP allocation..."
BEFORE=$(grep thp_fault_alloc /proc/vmstat | awk '{print $2}')
"$WORKDIR/touch_noopt" >/dev/null
AFTER=$(grep thp_fault_alloc /proc/vmstat | awk '{print $2}')
echo "[check] thp_fault_alloc before=$BEFORE after=$AFTER"
if [ "$AFTER" -gt "$BEFORE" ]; then
    fail "thp_fault_alloc increased ($BEFORE -> $AFTER) — the ordinary workload is still getting huge pages"
fi

echo "[PASS] THP is set to 'madvise' and the ordinary workload correctly does not receive huge pages."
exit 0
