#!/usr/bin/env bash
# Lab 16 check — is the fd-hog no longer hitting "too many open files"?
# Covers both the standalone script setup.sh starts, and the optional
# systemd unit (lab28-hog.service) built later in the README/challenges.
set -uo pipefail

PASS=0

check_process_fds() {
    local label="$1"
    local pid="$2"

    if ! kill -0 "$pid" 2>/dev/null; then
        echo "[check] $label (PID $pid) is not running - nothing to check, treating as resolved."
        return 0
    fi

    local limits_line soft fd_count
    limits_line=$(grep -i "open files" "/proc/$pid/limits" 2>/dev/null)
    if [ -z "$limits_line" ]; then
        echo "[FAIL] $label (PID $pid) is running but /proc/$pid/limits is unreadable."
        return 1
    fi
    soft=$(echo "$limits_line" | awk '{print $4}')
    fd_count=$(ls "/proc/$pid/fd" 2>/dev/null | wc -l)

    echo "[check] $label (PID $pid): soft nofile limit=$soft, current open fds=$fd_count"

    if [ "$soft" -le 64 ]; then
        echo "[FAIL] $label is still running under the original artificially-low limit ($soft) - not fixed."
        return 1
    fi

    if [ "$fd_count" -ge $((soft - 2)) ]; then
        echo "[FAIL] $label is at/near its fd ceiling ($fd_count of $soft) - still exhausted."
        return 1
    fi

    echo "[check] $label has headroom ($fd_count of $soft) - healthy."
    return 0
}

echo "[check] checking the standalone fd_hog.py process (setup.sh)..."
if [ -f /var/tmp/lab28/hog.pid ]; then
    HOGPID=$(cat /var/tmp/lab28/hog.pid 2>/dev/null)
    if [ -n "$HOGPID" ]; then
        if ! check_process_fds "standalone fd_hog.py" "$HOGPID"; then
            PASS=1
        fi
    fi
else
    echo "[check] no /var/tmp/lab28/hog.pid found - skipping standalone check."
fi

echo "[check] checking optional systemd unit lab28-hog.service, if it exists..."
if systemctl list-unit-files lab28-hog.service >/dev/null 2>&1 && systemctl list-unit-files lab28-hog.service | grep -q lab28-hog; then
    STATE=$(systemctl is-active lab28-hog.service 2>&1)
    echo "[check] lab28-hog.service is-active: $STATE"
    if [ "$STATE" = "active" ]; then
        SVCPID=$(systemctl show -p MainPID --value lab28-hog.service 2>/dev/null)
        if [ -n "$SVCPID" ] && [ "$SVCPID" != "0" ]; then
            if ! check_process_fds "lab28-hog.service" "$SVCPID"; then
                PASS=1
            fi
        fi
    else
        echo "[FAIL] lab28-hog.service exists but is not active (state: $STATE)."
        journalctl -u lab28-hog.service -n 10 --no-pager 2>&1 | tail -10
        PASS=1
    fi
else
    echo "[check] lab28-hog.service not present - skipping (it's only created later in the lab, not by setup.sh)."
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] no fd-hog process is currently exhausted or crash-looping on open files."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
