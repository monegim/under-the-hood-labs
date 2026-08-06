#!/usr/bin/env bash
# Lab 21 check — is chronyd running and synchronized, is the system clock
# actually correct (small offset from a real reference), and does the
# local HTTPS test endpoint's certificate now validate?
set -uo pipefail

PASS=0

echo "[check] is chronyd running (not masked/stopped)?"
if systemctl is-active --quiet chrony; then
    echo "[check] chrony is active."
else
    echo "[FAIL] chrony is not active: $(systemctl is-active chrony 2>&1)"
    PASS=1
fi

echo "[check] chronyc tracking..."
TRACKING=$(chronyc tracking 2>&1)
echo "$TRACKING"
if echo "$TRACKING" | grep -qi "Cannot talk to daemon"; then
    echo "[FAIL] chronyc cannot reach chronyd at all."
    PASS=1
elif echo "$TRACKING" | grep -q "^Leap status.*Normal"; then
    echo "[check] leap status is Normal (synchronized)."
else
    echo "[FAIL] chrony is not reporting a normal/synchronized leap status."
    PASS=1
fi

echo "[check] checking the system clock offset from chrony's own tracking data..."
OFFSET=$(echo "$TRACKING" | awk '/System time/{print $4}')
echo "[check] reported system time offset: ${OFFSET:-unknown} seconds"
if [ -n "${OFFSET:-}" ]; then
    OFFSET_INT=${OFFSET%.*}
    OFFSET_INT=${OFFSET_INT#-}
    if [ "${OFFSET_INT:-999}" -gt 5 ] 2>/dev/null; then
        echo "[FAIL] system clock offset is still large (${OFFSET}s) - not corrected yet."
        PASS=1
    else
        echo "[check] offset is small - clock looks corrected."
    fi
else
    echo "[FAIL] could not parse a system time offset from chronyc tracking."
    PASS=1
fi

echo "[check] does the local HTTPS test endpoint's certificate validate now?"
if curl -s --max-time 5 https://localhost:8443/ -o /dev/null 2>/var/tmp/lab21_curl_err.log; then
    echo "[check] curl succeeded - certificate validated."
else
    echo "[FAIL] curl still fails against the local HTTPS endpoint:"
    cat /var/tmp/lab21_curl_err.log 2>/dev/null
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] chrony is running/synchronized, the clock is correct, and TLS validation succeeds."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
