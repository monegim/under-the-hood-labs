#!/usr/bin/env bash
# Lab 9 setup — InnoDB's redo log capacity is set deliberately tiny
# (8MB, the documented minimum for innodb_redo_log_capacity on
# MySQL 8.0.30+), then a heavy write workload hammers a wide table. With
# so little redo log space, InnoDB has to keep the checkpoint LSN close
# behind the current LSN at all times, which means constant aggressive
# ("furious") flushing of dirty pages instead of the normal lazy
# background flush — writes visibly slow down under sustained load.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary (innodb_redo_log_capacity=8MB, deliberately tiny)..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab09-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[setup] lab09-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: lab09-primary never became healthy, check 'docker logs lab09-primary'"
    exit 1
  fi
done

echo "[setup] confirming the redo log capacity actually took effect..."
docker exec lab09-primary mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'innodb_redo_log_capacity';"

echo "[setup] creating a wide table (big rows generate more redo per write)..."
docker exec lab09-primary mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS events;
  CREATE TABLE events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    payload TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );
"

echo "[setup] baseline LOG section before load:"
docker exec lab09-primary mysql -uroot -prootpass -e "SHOW ENGINE INNODB STATUS\G" \
  | sed -n '/^---$/,/^-------/p' | grep -E "Log sequence number|Log flushed up to|Last checkpoint at" || true

echo "[setup] running a bounded heavy write workload (200 batches x 20 rows x ~4KB payload)..."
echo "[setup] timing it — note how long this takes, you'll compare it to the post-fix timing:"
START=$(date +%s)
docker exec lab09-primary bash -c '
  PAYLOAD=$(printf "x%.0s" $(seq 1 4000))
  for i in $(seq 1 200); do
    vals=""
    for j in $(seq 1 20); do
      vals="$vals,(\"$PAYLOAD\")"
    done
    vals="${vals#,}"
    mysql -uroot -prootpass appdb -e "INSERT INTO events (payload) VALUES $vals;" 2>/dev/null
  done
'
END=$(date +%s)
echo "[setup] write workload took $((END - START)) seconds (200 batches of 20 rows x ~4KB)"

echo "[setup] LOG section after load — checkpoint age should be pinned close to capacity:"
docker exec lab09-primary mysql -uroot -prootpass -e "SHOW ENGINE INNODB STATUS\G" \
  | sed -n '/^---$/,/^-------/p' | grep -E "Log sequence number|Log flushed up to|Last checkpoint at" || true

echo "[setup] done. Start diagnosing with:"
echo "  docker exec lab09-primary mysql -uroot -prootpass -e \"SHOW ENGINE INNODB STATUS\\G\" | less"
