#!/usr/bin/env bash
# Lab 18 check — is configapp.service currently active (config load
# succeeded), not stuck restart-looping on the missing-cwd bug?
set -uo pipefail

PASS=0

echo "[check] checking configapp.service status..."
STATE=$(systemctl is-active configapp 2>&1)
echo "[check] configapp.service is-active: $STATE"

if [ "$STATE" = "active" ]; then
    echo "[check] configapp.service is active."
else
    echo "[FAIL] configapp.service is not active (state: $STATE)."
    systemctl status configapp --no-pager -l 2>&1 | head -15
    PASS=1
fi

echo "[check] confirming the config actually loaded (not just that the process is up)..."
if journalctl -u configapp --no-pager 2>/dev/null | tail -20 | grep -q "config loaded ok"; then
    echo "[check] found 'config loaded ok' in the journal."
else
    echo "[FAIL] never saw 'config loaded ok' in recent journal output - it may be up for an unrelated reason."
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] configapp.service is active and successfully loaded its config."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
