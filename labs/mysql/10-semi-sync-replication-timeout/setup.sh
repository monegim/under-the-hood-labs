#!/usr/bin/env bash
# Lab 10 setup — a normal GTID primary/replica pair, upgraded to
# semi-synchronous replication: the primary will wait (up to a configured
# timeout) for the replica to ACK receipt of a transaction's binlog event
# before returning "commit OK" to the client. This buys a durability
# guarantee async replication doesn't have — but only while it's actually
# working, which is the point of this lab.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary and replica..."
docker compose up -d

echo "[setup] waiting for primary and replica to report healthy..."
for svc in lab10-primary lab10-replica; do
  for i in $(seq 1 60); do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$svc" 2>/dev/null || echo "starting")
    if [ "$status" = "healthy" ]; then
      echo "[setup] $svc is healthy"
      break
    fi
    sleep 3
    if [ "$i" -eq 60 ]; then
      echo "[setup] ERROR: $svc never became healthy, check 'docker logs $svc'"
      exit 1
    fi
  done
done

echo "[setup] creating replication user on primary..."
docker exec lab10-primary mysql -uroot -prootpass -e "
  CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'replpass';
  GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
  FLUSH PRIVILEGES;
"

echo "[setup] installing the semi-sync SOURCE plugin on primary..."
docker exec lab10-primary mysql -uroot -prootpass -e "
  INSTALL PLUGIN rpl_semi_sync_source SONAME 'semisync_master.so';
"

echo "[setup] installing the semi-sync REPLICA plugin on replica..."
docker exec lab10-replica mysql -uroot -prootpass -e "
  INSTALL PLUGIN rpl_semi_sync_replica SONAME 'semisync_slave.so';
"

echo "[setup] pointing replica at primary (GTID auto-position)..."
docker exec lab10-replica mysql -uroot -prootpass -e "
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='primary',
    SOURCE_USER='repl',
    SOURCE_PASSWORD='replpass',
    SOURCE_AUTO_POSITION=1;
"

echo "[setup] enabling semi-sync on replica, then starting replication..."
docker exec lab10-replica mysql -uroot -prootpass -e "
  SET GLOBAL rpl_semi_sync_replica_enabled = 1;
  START REPLICA;
"

echo "[setup] enabling semi-sync on primary (3 second ACK timeout, deliberately short for this lab)..."
docker exec lab10-primary mysql -uroot -prootpass -e "
  SET GLOBAL rpl_semi_sync_source_enabled = 1;
  SET GLOBAL rpl_semi_sync_source_timeout = 3000;
"

sleep 2
echo "[setup] confirming semi-sync is actually active (not just configured):"
docker exec lab10-primary mysql -uroot -prootpass -e "
  SHOW STATUS LIKE 'Rpl_semi_sync_source_status';
  SHOW STATUS LIKE 'Rpl_semi_sync_source_clients';
"

echo "[setup] creating schema and writing a few rows to confirm semi-sync commits are working..."
docker exec lab10-primary mysql -uroot -prootpass appdb -e "
  CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );
  INSERT INTO orders (data) VALUES ('warmup-1'), ('warmup-2'), ('warmup-3');
"

echo "[setup] done. Rpl_semi_sync_source_status should read ON above."
echo "[setup] Start diagnosing with:"
echo "  docker exec lab10-primary mysql -uroot -prootpass -e \"SHOW STATUS LIKE 'Rpl_semi_sync%';\""
