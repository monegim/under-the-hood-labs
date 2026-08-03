#!/usr/bin/env bash
# Lab 6 setup — MySQL's OWN disk usage patterns fill up disk, not generic
# inode exhaustion (that's Lab 11 in the linux track). Mechanism: binary
# logging is on, nobody ever configured purging
# (binlog_expire_logs_seconds=0, the old "never expire" default many
# upgraded-from-5.7 configs still carry), and a normal write workload
# rotates through binlog files that just accumulate forever.
#
# Safety: binlogs and tmpdir are pointed at small DEDICATED loop-mounted
# filesystems (150M / 100M), never the host's real disk or MySQL's actual
# datadir — filling them up is safe and fully reversible (umount +
# losetup -d), same technique as linux/11-disk-full-writes-fail.
set -euo pipefail

echo "[1/7] Installing mysql-server..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server > /dev/null

echo "[2/7] Stopping mysql to reconfigure binlog/tmp locations..."
sudo systemctl stop mysql

echo "[3/7] Creating a 150M loop-mounted filesystem for binary logs..."
sudo mkdir -p /var/lib/mysqllab06
sudo dd if=/dev/zero of=/var/lib/mysqllab06/binlogs.img bs=1M count=150 status=none
BINLOG_LOOPDEV=$(sudo losetup --find --show /var/lib/mysqllab06/binlogs.img)
echo "$BINLOG_LOOPDEV" | sudo tee /var/lib/mysqllab06/binlog-loopdev > /dev/null
sudo mkfs.ext4 -q "$BINLOG_LOOPDEV"
sudo mkdir -p /mnt/mysql-binlogs
sudo mount "$BINLOG_LOOPDEV" /mnt/mysql-binlogs

echo "[4/7] Creating a 100M loop-mounted filesystem for tmpdir..."
sudo dd if=/dev/zero of=/var/lib/mysqllab06/tmp.img bs=1M count=100 status=none
TMP_LOOPDEV=$(sudo losetup --find --show /var/lib/mysqllab06/tmp.img)
echo "$TMP_LOOPDEV" | sudo tee /var/lib/mysqllab06/tmp-loopdev > /dev/null
sudo mkfs.ext4 -q "$TMP_LOOPDEV"
sudo mkdir -p /mnt/mysql-tmp
sudo mount "$TMP_LOOPDEV" /mnt/mysql-tmp

echo "[5/7] Handing both to mysql and pointing mysqld at them..."
sudo chown mysql:mysql /mnt/mysql-binlogs /mnt/mysql-tmp
sudo tee /etc/mysql/mysql.conf.d/zzz-lab06.cnf > /dev/null <<'EOF'
[mysqld]
log-bin=/mnt/mysql-binlogs/mysql-bin
max_binlog_size=20M
binlog_expire_logs_seconds=0
tmpdir=/mnt/mysql-tmp
EOF

echo "[6/7] Starting mysqld and setting a root password..."
sudo systemctl start mysql
sleep 3
sudo mysql -e "
  ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'rootpass';
  FLUSH PRIVILEGES;
" 2>/dev/null || true

mysql -uroot -prootpass -e "
  CREATE DATABASE IF NOT EXISTS appdb;
  USE appdb;
  DROP TABLE IF EXISTS logs;
  CREATE TABLE logs (id INT AUTO_INCREMENT PRIMARY KEY, payload TEXT);
"

echo "[7/7] Writing until the dedicated binlog filesystem is nearly full"
echo "      (bounded at 400 iterations as a safety net)..."
set +e
for i in $(seq 1 400); do
  USE_PCT=$(df --output=pcent /mnt/mysql-binlogs | tail -1 | tr -d ' %')
  if [ "$USE_PCT" -ge 92 ]; then
    echo "[setup] /mnt/mysql-binlogs at ${USE_PCT}% - stopping the write workload."
    break
  fi
  VALS=""
  for j in $(seq 1 50); do
    VALS="$VALS,(REPEAT('x', 2000))"
  done
  VALS="${VALS#,}"
  mysql -uroot -prootpass appdb -e "INSERT INTO logs (payload) VALUES $VALS;" 2>/tmp/lab06-insert-err.log
  if [ $? -ne 0 ]; then
    echo "[setup] insert failed at iteration $i (disk full) - stopping:"
    cat /tmp/lab06-insert-err.log
    break
  fi
done
set -e

echo
echo "Done. Current state:"
df -h /mnt/mysql-binlogs
mysql -uroot -prootpass -e "SHOW BINARY LOGS;" 2>&1 | tail -15
echo
echo "Start diagnosing:"
echo "  df -h /mnt/mysql-binlogs"
echo "  mysql -uroot -prootpass -e \"SHOW BINARY LOGS;\""
echo "  mysql -uroot -prootpass appdb -e \"INSERT INTO logs (payload) VALUES ('test');\""
