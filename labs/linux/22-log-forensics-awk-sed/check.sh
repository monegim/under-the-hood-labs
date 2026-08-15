#!/usr/bin/env bash
# Lab 22 check — independently recomputes which IP is responsible for
# the most traffic in the last 10 minutes of whatever log data currently
# exists (so this works whether you're on the base scenario or
# Challenge B's appended burst), then verifies that IP is iptables-DROPed.
set -uo pipefail

LOGDIR=/var/tmp/lab22-logs

if [ ! -d "$LOGDIR" ] || [ -z "$(ls -A "$LOGDIR" 2>/dev/null)" ]; then
    echo "[FAIL] $LOGDIR is missing or empty — run setup.sh first."
    exit 1
fi

echo "[check] finding the max timestamp across all log files..."
MAX_TS=$(cat "$LOGDIR"/access.log.* | awk '{print $2}' | sort | tail -1)
if [ -z "$MAX_TS" ]; then
    echo "[FAIL] could not determine a max timestamp from the logs."
    exit 1
fi
echo "[check] max timestamp: $MAX_TS"

# ISO8601 timestamps sort lexicographically = chronologically, so we can
# compute "10 minutes before MAX_TS" with plain string comparison once we
# have the cutoff — computed via python3 to avoid GNU/BSD `date` syntax
# differences entirely.
CUTOFF=$(python3 -c "
import sys
from datetime import datetime, timedelta
ts = datetime.strptime('$MAX_TS', '%Y-%m-%dT%H:%M:%SZ')
print((ts - timedelta(minutes=10)).strftime('%Y-%m-%dT%H:%M:%SZ'))
")
if [ -z "$CUTOFF" ]; then
    echo "[FAIL] could not compute the 10-minute cutoff."
    exit 1
fi
echo "[check] trailing-10-minute window: $CUTOFF to $MAX_TS"

TOP_IP=$(cat "$LOGDIR"/access.log.* \
  | awk -v cutoff="$CUTOFF" '$2 >= cutoff {print $1}' \
  | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')

if [ -z "$TOP_IP" ]; then
    echo "[FAIL] could not determine a top IP for the trailing window."
    exit 1
fi
echo "[check] top IP in the trailing 10-minute window: $TOP_IP"

echo "[check] is $TOP_IP currently DROPed via iptables?"
if sudo iptables -L INPUT -n 2>/dev/null | grep -q "DROP.*${TOP_IP}\|${TOP_IP}.*DROP"; then
    echo "[PASS] $TOP_IP (the actual current top offender) is blocked."
    exit 0
else
    echo "[FAIL] $TOP_IP is currently the top offender in the last 10 minutes of log data, but is NOT blocked."
    exit 1
fi
