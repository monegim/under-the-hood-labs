#!/usr/bin/env bash
# Lab 8 reset — kill every leftover storm process and DB session, restore
# the lab's baseline config, then re-run setup.sh to reproduce the storm.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] killing leftover storm client processes..."
if [ -f /tmp/lab08-pids/storm.pids ]; then
  while read -r pid; do
    kill -9 "$pid" 2>/dev/null || true
  done < /tmp/lab08-pids/storm.pids
fi
rm -rf /tmp/lab08-pids

echo "[reset] killing any lingering appuser sessions on the server..."
mysql -uroot -prootpass -N -e "
  SELECT CONCAT('KILL ', id, ';') FROM information_schema.processlist WHERE user='appuser';
" 2>/dev/null | mysql -uroot -prootpass 2>/dev/null || true

echo "[reset] restoring baseline max_connections=50 (in case Step 5's emergency"
echo "        bump is still active from a previous run)..."
sudo tee /etc/mysql/mysql.conf.d/zzz-lab08.cnf > /dev/null <<'EOF'
[mysqld]
max_connections=50
EOF
sudo systemctl restart mysql
sleep 2

echo "[reset] re-running setup.sh to reproduce the connection storm..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
