#!/usr/bin/env bash
# Lab 2 setup — GTID-based replication broken by an "errant transaction":
# a write made directly on the replica (root bypasses --read-only, same as
# a broken failover runbook or an accidental direct write to what everyone
# THOUGHT was still a plain replica) creates a GTID under the replica's own
# server UUID. When the primary later writes a row that collides with it,
# the replica's SQL thread stops dead with a duplicate-key error tied to
# that GTID — and simply restarting replication does not fix it, because
# GTID auto-positioning means the source keeps resending the exact same
# transaction forever.
#
# Safety note: everything here runs inside throwaway containers with bind
# mounts under ./data — nothing touches the host's real MySQL, if any.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary and replica..."
docker compose up -d

echo "[setup] waiting for primary and replica to report healthy..."
for svc in lab02-primary lab02-replica; do
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
docker exec lab02-primary mysql -uroot -prootpass -e "
  CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'replpass';
  GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
  FLUSH PRIVILEGES;
"

echo "[setup] pointing replica at primary (GTID auto-position)..."
docker exec lab02-replica mysql -uroot -prootpass -e "
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='primary',
    SOURCE_USER='repl',
    SOURCE_PASSWORD='replpass',
    SOURCE_AUTO_POSITION=1;
  START REPLICA;
"

sleep 3
echo "[setup] replica status:"
docker exec lab02-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source"

echo "[setup] creating schema on primary (id is an explicit business key, not auto_increment,"
echo "[setup] so we can deterministically engineer the collision below)..."
docker exec lab02-primary mysql -uroot -prootpass appdb -e "
  CREATE TABLE IF NOT EXISTS orders (
    id INT PRIMARY KEY,
    data VARCHAR(255)
  );
"

sleep 2
echo "[setup] seeding a few baseline rows on primary and letting them replicate..."
docker exec lab02-primary mysql -uroot -prootpass appdb -e "
  INSERT INTO orders (id, data) VALUES (1, 'seed-1'), (2, 'seed-2'), (3, 'seed-3');
"
sleep 3

echo "[setup] --- simulating the incident ---"
echo "[setup] pausing replication (imagine: a short maintenance window, or a brief"
echo "[setup] failover where this node was momentarily treated as writable)..."
docker exec lab02-replica mysql -uroot -prootpass -e "STOP REPLICA;"

echo "[setup] writing DIRECTLY to the replica (root bypasses --read-only=ON) —"
echo "[setup] this commits under the REPLICA's own server UUID, not the primary's."
docker exec lab02-replica mysql -uroot -prootpass appdb -e "
  INSERT INTO orders (id, data) VALUES (9999, 'written-directly-on-replica-by-mistake');
"
REPLICA_UUID=$(docker exec lab02-replica mysql -uroot -prootpass -N -e "SELECT @@server_uuid;")
echo "[setup] errant transaction now lives under GTID ${REPLICA_UUID}:1 (replica-only, source never saw it)"

echo "[setup] meanwhile the app keeps writing to the PRIMARY as normal, including"
echo "[setup] a row that — through no coincidence in this lab — reuses id=9999..."
docker exec lab02-primary mysql -uroot -prootpass appdb -e "
  INSERT INTO orders (id, data) VALUES (4, 'primary-4'), (5, 'primary-5');
  INSERT INTO orders (id, data) VALUES (9999, 'the-real-order-9999-from-primary');
"

echo "[setup] resuming replication — the SQL thread will now try to apply primary's"
echo "[setup] id=9999 INSERT against a replica that already has its own id=9999 row..."
docker exec lab02-replica mysql -uroot -prootpass -e "START REPLICA;"

sleep 3
echo "[setup] done. Expected result: Replica_SQL_Running=No, Last_SQL_Errno=1062."
echo "[setup] Start diagnosing:"
echo "    docker exec lab02-replica mysql -uroot -prootpass -e \"SHOW REPLICA STATUS\\G\""
