#!/usr/bin/env bash
# Lab 14 reset — kill any lingering lab writer processes (main lab + both
# challenges), clean up their workdirs, then re-run setup.sh's steps (start
# writer, delete file out from under it) to recreate the scenario.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] killing any lingering lab26/lab26b writer processes..."
for pidfile in /var/tmp/lab26/writer.pid /var/tmp/lab26b/parent.pid /var/tmp/lab26b/child.pid; do
    if [ -f "$pidfile" ]; then
        PID=$(cat "$pidfile" 2>/dev/null)
        if [ -n "$PID" ]; then
            kill "$PID" 2>/dev/null || true
        fi
    fi
done
# Belt-and-suspenders: catch any remaining processes matching the lab's
# writer command lines (covers Challenge A's second setup.sh run too).
pkill -f "exec 3>>.*lab26" 2>/dev/null || true
sleep 1
pkill -9 -f "exec 3>>.*lab26" 2>/dev/null || true

echo "[reset] removing lab work directories..."
rm -rf /var/tmp/lab26 /var/tmp/lab26b

echo "[reset] re-running setup.sh to recreate the deleted-but-open-file incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
