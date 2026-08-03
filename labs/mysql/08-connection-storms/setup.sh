#!/usr/bin/env bash
# Lab 8 setup — a broken connection pool (simulated here as a plain loop
# that opens new connections instead of reusing them, and never closes
# any) exhausts max_connections. New legitimate connections from the same
# app user get rejected with "Too many connections."
#
# max_connections is set deliberately low (50) so this reproduces fast
# without needing hundreds of real processes. A dedicated low-privilege
# 'appuser' holds the storm connections — root keeps working throughout,
# via MySQL's one reserved extra connection for SUPER/CONNECTION_ADMIN
# users, which is exactly the real mechanism that lets an on-call DBA get
# in during a real connection-storm incident.
set -euo pipefail

echo "[1/6] Installing mysql-server..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server > /dev/null

echo "[2/6] Setting a root password so the rest of this lab can script non-interactively..."
sudo mysql -e "
  ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'rootpass';
  FLUSH PRIVILEGES;
" 2>/dev/null || true

echo "[3/6] Setting max_connections=50 (deliberately low) and leaving wait_timeout"
echo "      at its long 8-hour default — nothing will reap idle app connections on its own..."
sudo tee /etc/mysql/mysql.conf.d/zzz-lab08.cnf > /dev/null <<'EOF'
[mysqld]
max_connections=50
EOF
sudo systemctl restart mysql
sleep 2

echo "[4/6] Creating a low-privilege app user (no SUPER/CONNECTION_ADMIN —"
echo "      unlike root, appuser has no reserved extra connection)..."
mysql -uroot -prootpass -e "
  CREATE DATABASE IF NOT EXISTS appdb;
  CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED WITH mysql_native_password BY 'appuserpass';
  GRANT ALL PRIVILEGES ON appdb.* TO 'appuser'@'%';
  FLUSH PRIVILEGES;
"

echo "[5/6] Simulating a broken connection pool: 70 connections as 'appuser',"
echo "      each opened separately and held open (bounded at 180s, self-terminating)"
echo "      instead of the pool reusing a small fixed set of connections..."
mkdir -p /tmp/lab08-pids
for i in $(seq 1 70); do
  nohup mysql -uappuser -pappuserpass appdb -e "DO SLEEP(180);" > /dev/null 2>&1 &
  echo $! >> /tmp/lab08-pids/storm.pids
done

sleep 3
echo "[6/6] Confirming the storm and a legitimate new connection failing..."
mysql -uroot -prootpass -e "SHOW STATUS LIKE 'Threads_connected';"
echo "--- attempting a new connection as appuser (this is what the app's next request looks like) ---"
mysql -uappuser -pappuserpass appdb -e "SELECT 1;" || true

echo
echo "Done. Start diagnosing (root still works via its reserved connection):"
echo "  mysql -uroot -prootpass -e \"SHOW STATUS LIKE 'Threads_connected';\""
echo "  mysql -uroot -prootpass -e \"SHOW PROCESSLIST;\" | head -30"
