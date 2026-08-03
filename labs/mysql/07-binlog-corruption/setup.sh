#!/usr/bin/env bash
# Lab 7 setup — a binlog file the replica still needs gets corrupted at
# rest on the primary (simulating disk bitrot / a bad block / accidental
# partial write — never do this to a real system, only a throwaway
# container). The replica's IO thread errors out trying to read past the
# corrupted bytes. Deliberately corrupts an OLD, already-rotated binlog
# file (not the currently active one) while the primary is stopped — an
# already-rotated file is closed with its own Rotate event and is NOT
# touched by MySQL's crash-recovery scan at startup (that only inspects
# the log that was active when the server last stopped), so this
# reliably stays corrupted instead of MySQL silently "fixing" it for us.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary and replica..."
docker compose up -d

echo "[setup] waiting for primary and replica to report healthy..."
for svc in lab07-primary lab07-replica; do
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
docker exec lab07-primary mysql -uroot -prootpass -e "
  CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'replpass';
  GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
  FLUSH PRIVILEGES;
"

echo "[setup] pointing replica at primary (GTID auto-position)..."
docker exec lab07-replica mysql -uroot -prootpass -e "
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='primary',
    SOURCE_USER='repl',
    SOURCE_PASSWORD='replpass',
    SOURCE_AUTO_POSITION=1;
  START REPLICA;
"
sleep 3

echo "[setup] creating schema and seeding data, letting it replicate..."
docker exec lab07-primary mysql -uroot -prootpass appdb -e "
  CREATE TABLE IF NOT EXISTS orders (id INT AUTO_INCREMENT PRIMARY KEY, data VARCHAR(255));
  INSERT INTO orders (data) VALUES ('seed-1'),('seed-2');
"
sleep 3

echo "[setup] --- simulating the incident ---"
echo "[setup] pausing the replica (imagine: routine maintenance window)..."
docker exec lab07-replica mysql -uroot -prootpass -e "STOP REPLICA;"

echo "[setup] generating several rounds of writes on the primary, force-rotating"
echo "[setup] the binlog between rounds, so multiple OLD binlog files pile up"
echo "[setup] containing transactions the stopped replica hasn't fetched yet..."
for round in 1 2 3 4; do
  docker exec lab07-primary mysql -uroot -prootpass appdb -e "
    INSERT INTO orders (data)
    SELECT REPEAT('r${round}-', 200) FROM
      (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) t1,
      (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) t2;
  "
  docker exec lab07-primary mysql -uroot -prootpass -e "FLUSH BINARY LOGS;"
done

echo "[setup] binlog files on primary now:"
docker exec lab07-primary mysql -uroot -prootpass -e "SHOW BINARY LOGS;"

echo "[setup] identifying the OLDEST rotated (non-active) binlog file to corrupt..."
BINLOGS=$(docker exec lab07-primary mysql -uroot -prootpass -N -e "SHOW BINARY LOGS;" | awk '{print $1}')
TARGET_FILE=$(echo "$BINLOGS" | head -2 | tail -1)
echo "[setup] target: $TARGET_FILE (deliberately NOT the currently active file)"

echo "[setup] stopping primary to safely corrupt the file at rest on disk..."
docker compose stop primary

TARGET_PATH="./data/primary/${TARGET_FILE}"
if [ ! -f "$TARGET_PATH" ]; then
  echo "[setup] ERROR: expected binlog file not found at $TARGET_PATH"
  exit 1
fi
FILESIZE=$(stat -c%s "$TARGET_PATH" 2>/dev/null || stat -f%z "$TARGET_PATH")
MIDPOINT=$((FILESIZE / 2))
echo "[setup] corrupting $TARGET_PATH at byte offset $MIDPOINT (size ${FILESIZE}b)..."
sudo dd if=/dev/urandom of="$TARGET_PATH" bs=1 seek="$MIDPOINT" count=256 conv=notrunc status=none 2>/dev/null \
  || dd if=/dev/urandom of="$TARGET_PATH" bs=1 seek="$MIDPOINT" count=256 conv=notrunc status=none

echo "[setup] bringing primary back up..."
docker compose start primary
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab07-primary 2>/dev/null || echo "starting")
  [ "$status" = "healthy" ] && break
  sleep 3
done

echo "[setup] resuming the replica — its IO thread will try to read forward from"
echo "[setup] where it left off, which is inside the now-corrupted file..."
docker exec lab07-replica mysql -uroot -prootpass -e "START REPLICA;"
sleep 3

echo
echo "Done. Expected: Replica_IO_Running=No, Last_IO_Error mentioning a read/parse failure."
echo "Start diagnosing:"
echo "  docker exec lab07-replica mysql -uroot -prootpass -e \"SHOW REPLICA STATUS\\G\""
