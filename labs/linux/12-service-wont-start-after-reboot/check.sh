#!/usr/bin/env bash
# Lab 12 check — is webapp.service currently active (running), not failed?
set -uo pipefail

PASS=0

echo "[check] checking webapp.service status..."
STATE=$(systemctl is-active webapp 2>&1)
echo "[check] webapp.service is-active: $STATE"

if [ "$STATE" = "active" ]; then
    echo "[check] webapp.service is active."
else
    echo "[FAIL] webapp.service is not active (state: $STATE)."
    systemctl status webapp --no-pager -l 2>&1 | head -15
    PASS=1
fi

echo "[check] confirming mysql.service (webapp's dependency) is active..."
if systemctl is-active --quiet mysql; then
    echo "[check] mysql.service is active."
else
    echo "[FAIL] mysql.service is not active - webapp cannot stay healthy without it."
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] webapp.service is active (running) and mysql.service is up."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
