#!/usr/bin/env bash
# Incident 11 setup - builds the entire broken environment:
#   primary          - MySQL 8.0, source of truth, every write lands here
#   replica           - MySQL 8.0, read-only, replicating from primary
#   reporting-job     - an unrelated container doing heavy synchronous writes
#                       to a directory that shares the SAME underlying host
#                       disk as the replica's datadir (same trick as
#                       incident 04 / labs/mysql/01), which keeps the
#                       replica genuinely, continuously a little behind
#   app               - a notes service: POST /save writes to primary,
#                       GET /note reads from the REPLICA by default - that
#                       read-from-replica choice is the incident
#
# By the time this script finishes, reporting-job is already contending for
# the replica's disk and the replica is already running behind - the
# incident is live, same as walking onto a real page.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[1/6] Preparing host directories (replica datadir + reporting scratch, siblings on the same disk)..."
mkdir -p ./data/primary ./data/replica-disk/mysql ./data/replica-disk/reporting-scratch

echo "[2/6] Building and starting primary, replica, reporting-job, app..."
docker compose up -d --build

echo "[3/6] Waiting for primary and replica to report healthy..."
for svc in incident11-primary incident11-replica; do
  for i in $(seq 1 40); do
    status=$(docker inspect --format='{{.State.Health.Status}}' "$svc" 2>/dev/null || echo "starting")
    [ "$status" = "healthy" ] && break
    sleep 3
    if [ "$i" -eq 40 ]; then
      echo "ERROR: $svc never became healthy, check 'docker logs $svc'"
      exit 1
    fi
  done
done

echo "[4/6] Creating replication user and schema on primary..."
docker exec incident11-primary mysql -uroot -prootpass -e "
  CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'replpass';
  GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
  FLUSH PRIVILEGES;
"
docker exec incident11-primary mysql -uroot -prootpass appdb -e "
  CREATE TABLE IF NOT EXISTS notes (
    id VARCHAR(64) PRIMARY KEY,
    text VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  );
"

echo "[5/6] Pointing replica at primary (GTID auto-position) and starting replication..."
docker exec incident11-replica mysql -uroot -prootpass -e "
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='primary',
    SOURCE_USER='repl',
    SOURCE_PASSWORD='replpass',
    SOURCE_AUTO_POSITION=1;
  START REPLICA;
"
sleep 3
echo "      replica status:"
docker exec incident11-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source" || true

echo "[6/6] Waiting for the app to answer /health..."
for i in $(seq 1 30); do
    curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health 2>/dev/null | grep -q 200 && break
    sleep 2
done

echo
echo "Confirming reporting-job is generating disk I/O on the replica's disk..."
sleep 5
docker logs incident11-reporting-job 2>&1 | tail -3 || true
docker exec incident11-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Seconds_Behind_Source" || true

echo
echo "Done. Environment is up and the incident is already in progress."
echo "  App:            http://localhost:8080"
echo "  Primary MySQL:  localhost:3306 (root/rootpass)"
echo "  Replica MySQL:  localhost:3307 (root/rootpass)"
echo
echo "Try:"
echo '  curl -s -X POST http://localhost:8080/save -H "Content-Type: application/json" -d "{\"id\":\"note-1\",\"text\":\"hello\"}"'
echo '  curl -s http://localhost:8080/note/note-1'
