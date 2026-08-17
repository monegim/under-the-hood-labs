#!/usr/bin/env bash
# Lab 17 setup — takes a full backup with its binlog position recorded,
# continues normal writes, then runs a DELETE with no WHERE clause (the
# disaster), followed by more normal writes afterward. The backup alone
# is not enough to recover — you need the backup PLUS everything in the
# binlog up to (but not including) the disaster.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary, restore target, and tools container..."
docker compose up -d

for svc in lab17-primary lab17-restore; do
  echo "[setup] waiting for $svc to report healthy..."
  for i in $(seq 1 60); do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$svc" 2>/dev/null || echo "starting")
    if [ "$status" = "healthy" ]; then
      echo "[setup] $svc is healthy"
      break
    fi
    sleep 3
    if [ "$i" -eq 60 ]; then
      echo "[setup] ERROR: $svc never became healthy" >&2
      exit 1
    fi
  done
done

echo "[setup] waiting for the tools container to finish installing mariadb-binlog..."
for i in $(seq 1 40); do
  if docker exec lab17-tools mariadb-binlog --version >/dev/null 2>&1; then
    echo "[setup] tools container is ready"
    break
  fi
  sleep 3
  if [ "$i" -eq 40 ]; then
    echo "[setup] ERROR: tools container never finished installing, check 'docker logs lab17-tools'" >&2
    exit 1
  fi
done

echo "[setup] creating schema and seed data..."
docker exec lab17-primary mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS accounts;
  CREATE TABLE accounts (id INT PRIMARY KEY, balance INT);
  INSERT INTO accounts VALUES (1, 100), (2, 200), (3, 300);
"

echo "[setup] taking a full backup (with binlog position recorded)..."
docker exec lab17-tools bash -c "
  mysqldump -h primary -uroot -prootpass --single-transaction --master-data=2 --databases appdb > /tmp/backup.sql
"
echo "[setup] backup's recorded position:"
docker exec lab17-tools grep "CHANGE MASTER" /tmp/backup.sql

echo "[setup] normal writes continue after the backup..."
docker exec lab17-primary mysql -uroot -prootpass appdb -e "
  INSERT INTO accounts VALUES (4, 400);
  UPDATE accounts SET balance = balance + 50 WHERE id = 1;
"

echo "[setup] THE DISASTER — a DELETE with no WHERE clause..."
docker exec lab17-primary mysql -uroot -prootpass appdb -e "DELETE FROM accounts;"

echo "[setup] normal writes continue AFTER the disaster too (not yet noticed)..."
docker exec lab17-primary mysql -uroot -prootpass appdb -e "INSERT INTO accounts VALUES (5, 500);"

echo "[setup] current (broken) state:"
docker exec lab17-primary mysql -uroot -prootpass appdb -e "SELECT * FROM accounts;"

echo "[setup] copying the binlog into the tools container for analysis..."
docker exec lab17-primary mysql -uroot -prootpass -N -e "SHOW BINARY LOGS;" | tail -1 | awk '{print $1}' > /tmp/lab17-binlog-name.txt
BINLOG=$(cat /tmp/lab17-binlog-name.txt)
docker cp "lab17-primary:/var/lib/mysql/${BINLOG}" "/tmp/lab17-${BINLOG}"
docker cp "/tmp/lab17-${BINLOG}" "lab17-tools:/tmp/${BINLOG}"

echo
echo "Done. Only 'id=5' survives — 1, 2, 3, and 4 are gone, and 4's data was never even in the backup."
echo "Binary log copied into the tools container as /tmp/${BINLOG}. Find the disaster's exact position:"
echo "  docker exec lab17-tools mariadb-binlog --base64-output=DECODE-ROWS -v /tmp/${BINLOG} | grep -B8 'DELETE FROM'"
