#!/usr/bin/env bash
# Lab 30 setup — the capstone: MySQL primary/replica replication, where
# replication lag spikes because something else on the replica's HOST is
# starving the disk the replica's datadir lives on.
#
# Safety note: every generator in this script is BOUNDED (fixed iteration
# counts / fixed durations), not an infinite "while true" loop. If you
# want another burst of contention after this script finishes, re-run
# Step 4 by hand (see README "Step 4" / "re-trigger contention").
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary, replica, io-hog..."
docker compose up -d

echo "[setup] waiting for primary and replica to report healthy..."
for svc in lab30-primary lab30-replica; do
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
docker exec lab30-primary mysql -uroot -prootpass -e "
  CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'replpass';
  GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
  FLUSH PRIVILEGES;
"

echo "[setup] pointing replica at primary (GTID auto-position, no manual log offsets)..."
docker exec lab30-replica mysql -uroot -prootpass -e "
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='primary',
    SOURCE_USER='repl',
    SOURCE_PASSWORD='replpass',
    SOURCE_AUTO_POSITION=1;
  START REPLICA;
"

sleep 3
echo "[setup] replica status:"
docker exec lab30-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source"

echo "[setup] creating schema on primary..."
docker exec lab30-primary mysql -uroot -prootpass appdb -e "
  CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );
"

echo "[setup] starting a bounded write workload against primary (background, ~3 min, self-terminating)..."
docker exec -d lab30-primary bash -c '
  for i in $(seq 1 300); do
    vals=""
    for j in $(seq 1 50); do
      vals="$vals,(REPEAT(char(120), 200))"
    done
    vals="${vals#,}"
    mysql -uroot -prootpass appdb -e "INSERT INTO orders (data) VALUES $vals;" 2>/dev/null
    sleep 0.5
  done
'

echo "[setup] starting bounded I/O contention on the replica host disk (background, self-terminating)..."
echo "[setup] 4 parallel writers x 40 iterations x 128MB, overwriting the SAME 4 files"
echo "[setup] each time (bounded disk usage, ~512MB resident, large total I/O throughput)"
docker exec -d lab30-io-hog bash -c '
  for w in 1 2 3 4; do
    (
      for i in $(seq 1 40); do
        dd if=/dev/zero of=/hogdata/hog-$w.dat bs=1M count=128 conv=fdatasync 2>/dev/null
      done
    ) &
  done
  wait
'

echo "[setup] done. Both background generators are running and will finish on their own"
echo "[setup] (writer: ~3 minutes, io-hog: until all 4 workers finish their 40 iterations)."
echo "[setup] Start diagnosing now:"
echo "    docker exec lab30-replica mysql -uroot -prootpass -e \"SHOW REPLICA STATUS\\G\" | grep Seconds_Behind_Source"
