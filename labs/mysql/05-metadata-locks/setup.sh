#!/usr/bin/env bash
# Lab 5 setup — a long-running (idle-in-transaction-shaped) transaction
# holds a metadata lock (MDL) on a table. A completely unrelated-looking
# ALTER TABLE then can't even START, and — because MySQL queues MDL
# requests fairly, to prevent starving the DDL forever — every ordinary
# SELECT/INSERT issued against the table AFTER the ALTER gets queued
# BEHIND it too, even though those statements would have been fine on
# their own.
#
# Safety note: the long-running transaction is bounded (5 min, self-
# terminating) so this incident resolves on its own even if left alone.
set -euo pipefail

echo "[1/5] Installing mysql-server..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server > /dev/null

echo "[2/5] Setting a root password so the rest of this lab can script non-interactively..."
sudo mysql -e "
  ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'rootpass';
  FLUSH PRIVILEGES;
" 2>/dev/null || true

echo "[3/5] Enabling the metadata-lock instrument in performance_schema (OFF by"
echo "      default in stock MySQL 8.0 — without this, performance_schema.metadata_locks"
echo "      stays empty even while locks are actively being held/waited on)..."
mysql -uroot -prootpass -e "
  UPDATE performance_schema.setup_instruments
  SET ENABLED='YES', TIMED='YES'
  WHERE NAME='wait/lock/metadata/sql/mdl';
"

echo "[3/5] Creating schema..."
mysql -uroot -prootpass -e "
  CREATE DATABASE IF NOT EXISTS appdb;
  USE appdb;
  DROP TABLE IF EXISTS orders;
  CREATE TABLE orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    status VARCHAR(20) NOT NULL DEFAULT 'new'
  );
  INSERT INTO orders (status) VALUES ('new'), ('new'), ('shipped');
"

echo "[4/5] Starting a long-running transaction that touched 'orders' and never"
echo "      commits (bounded at 300s, self-terminating) — imagine a report script"
echo "      or an ORM session that forgot to commit/close..."
nohup mysql -uroot -prootpass appdb -e "
  BEGIN;
  SELECT * FROM orders LIMIT 1;
  DO SLEEP(300);
  COMMIT;
" > /tmp/lab05-long-txn.log 2>&1 &
echo $! > /tmp/lab05-long-txn.pid
sleep 1

echo "[5/5] Now firing an ALTER TABLE (background) — it can't even start while"
echo "      the transaction above holds its metadata lock — followed by a few"
echo "      ordinary queries that should otherwise be totally unrelated..."
nohup mysql -uroot -prootpass appdb -e "
  ALTER TABLE orders ADD COLUMN notes VARCHAR(255);
" > /tmp/lab05-alter.log 2>&1 &
echo $! > /tmp/lab05-alter.pid
sleep 1

for i in 1 2 3; do
  nohup mysql -uroot -prootpass appdb -e "
    SELECT COUNT(*) FROM orders;
  " > "/tmp/lab05-query-$i.log" 2>&1 &
  echo $! > "/tmp/lab05-query-$i.pid"
done

sleep 2
echo
echo "Done. Everything below should be queued up and stuck:"
mysql -uroot -prootpass -e "
  SELECT id, user, command, time, state, LEFT(info,60) AS info
  FROM information_schema.processlist
  WHERE db='appdb'
  ORDER BY time DESC;
"
echo
echo "Start diagnosing:"
echo "  mysql -uroot -prootpass -e \"SHOW PROCESSLIST\\G\""
echo "  mysql -uroot -prootpass -e \"SELECT * FROM performance_schema.metadata_locks\\G\""
