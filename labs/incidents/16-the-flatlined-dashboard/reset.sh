#!/usr/bin/env bash
# Incident 16 reset - tears down every piece this incident touches and
# rebuilds it via setup.sh, so the incident (CPU hog + blocked NFS
# write) is freshly reproduced.
set -uo pipefail

echo "[reset] stopping services..."
sudo systemctl stop metrics-agent.service orders-api.service 2>/dev/null || true
sudo systemctl disable metrics-agent.service orders-api.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/metrics-agent.service /etc/systemd/system/orders-api.service
sudo systemctl daemon-reload

echo "[reset] killing any leftover CPU-hog processes..."
if [ -f /var/lib/metricslab/hog.pids ]; then
    while read -r pid; do
        sudo kill -9 "$pid" 2>/dev/null || true
    done < /var/lib/metricslab/hog.pids
fi
sudo pkill -9 -f "1103515245" 2>/dev/null || true
sudo rm -rf /var/lib/metricslab

echo "[reset] clearing the iptables DROP rules on port 2049 (if present)..."
sudo iptables -D OUTPUT -p tcp --dport 2049 -j DROP 2>/dev/null || true
sudo iptables -D INPUT -p tcp --sport 2049 -j DROP 2>/dev/null || true

echo "[reset] unmounting and removing the NFS export..."
sudo umount -f /mnt/metricslab 2>/dev/null || true
sudo sed -i '\#^/srv/metricslab #d' /etc/exports 2>/dev/null || true
sudo exportfs -ra 2>/dev/null || true
sudo rm -rf /srv/metricslab /mnt/metricslab

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[reset] re-running setup.sh to recreate the incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
