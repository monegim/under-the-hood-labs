#!/usr/bin/env bash
# Lab 25 check — verifies the drifted host (host2) was fixed, and that
# host1/host3 were never touched: no version change, no restart.log
# entry. This is exactly what distinguishes "fixed the right one" from
# "synchronize-panes fixed all three."
set -uo pipefail

LABDIR=/var/tmp/lab25
PASS=0

if [ ! -d "$LABDIR" ]; then
    echo "[FAIL] $LABDIR is missing — run setup.sh first."
    exit 1
fi

echo "[check] is host2 (the drifted one) fixed?"
H2_VERSION=$(cat "$LABDIR/host2/version.txt" 2>/dev/null || echo "")
echo "[check] host2 version: $H2_VERSION"
if [ "$H2_VERSION" != "v2.3.1" ]; then
    echo "[FAIL] host2 is still on the wrong version."
    PASS=1
fi

H2_RESTARTS=$(grep -c "restarted" "$LABDIR/host2/restart.log" 2>/dev/null)
H2_RESTARTS=${H2_RESTARTS:-0}
echo "[check] host2 restart.log entries: $H2_RESTARTS"
if [ "$H2_RESTARTS" -lt 1 ]; then
    echo "[FAIL] host2 has no restart record — was it actually fixed?"
    PASS=1
fi

echo "[check] were host1 and host3 left alone?"
for h in host1 host3; do
    VERSION=$(cat "$LABDIR/$h/version.txt" 2>/dev/null || echo "")
    if [ "$VERSION" != "v2.3.1" ]; then
        echo "[FAIL] $h's version changed unexpectedly (now '$VERSION') — it should never have needed fixing."
        PASS=1
    fi
    RESTARTS=$(grep -c "restarted" "$LABDIR/$h/restart.log" 2>/dev/null)
    RESTARTS=${RESTARTS:-0}
    if [ "$RESTARTS" -ne 0 ]; then
        echo "[FAIL] $h/restart.log has $RESTARTS entr(y/ies) — it was restarted when it never should have been. This is exactly the synchronize-panes trap."
        PASS=1
    fi
done

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] host2 fixed correctly, host1/host3 completely untouched."
    exit 0
else
    echo "[FAIL] see details above."
    exit 1
fi
