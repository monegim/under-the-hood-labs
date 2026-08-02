#!/usr/bin/env bash
# Lab 16 reset — kill the standalone hog and any systemd-managed variant
# built during the lab, revert limits.conf lines added as a (correct or
# incorrect) fix, then re-run setup.sh to recreate the EMFILE incident.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] killing the standalone fd_hog.py process, if running..."
if [ -f /var/tmp/lab28/hog.pid ]; then
    HOGPID=$(cat /var/tmp/lab28/hog.pid 2>/dev/null)
    [ -n "$HOGPID" ] && kill "$HOGPID" 2>/dev/null || true
fi
pkill -f "fd_hog.py" 2>/dev/null || true

echo "[reset] stopping/removing the optional lab28-hog.service systemd unit, if present..."
sudo systemctl stop lab28-hog.service 2>/dev/null || true
sudo systemctl disable lab28-hog.service 2>/dev/null || true
sudo rm -rf /etc/systemd/system/lab28-hog.service.d
sudo rm -f /etc/systemd/system/lab28-hog.service
sudo systemctl daemon-reload
sudo systemctl reset-failed 2>/dev/null || true

echo "[reset] reverting limits.conf lines added during the lab/challenges, if present..."
sudo sed -i \
    -e '/^appuser soft nofile 65536$/d' \
    -e '/^appuser hard nofile 65536$/d' \
    -e '/^root soft nofile 65536$/d' \
    -e '/^root hard nofile 65536$/d' \
    /etc/security/limits.conf 2>/dev/null || true

echo "[reset] re-running setup.sh to recreate the fd exhaustion incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
