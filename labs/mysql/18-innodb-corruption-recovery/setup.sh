#!/usr/bin/env bash
# Lab 18 setup — corrupts only the 4-byte checksum field of one InnoDB
# data page on disk (simulating bit-rot or a torn write hitting exactly
# those bytes), leaving every actual row byte on that page untouched.
# Done safely on a throwaway container while it's stopped, matching the
# established pattern from 07-binlog-corruption. On restart, InnoDB
# detects the checksum mismatch and — by design, as a safety measure —
# crashes rather than risk serving unverified data.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab18-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[setup] lab18-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: lab18-primary never became healthy" >&2
    exit 1
  fi
done
sleep 5

echo "[setup] creating a table with enough rows to span multiple 16KB pages..."
docker exec lab18-primary mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS orders;
  CREATE TABLE orders (id INT AUTO_INCREMENT PRIMARY KEY, data VARCHAR(255));
  INSERT INTO orders (data)
  SELECT REPEAT('x', 200) FROM
    (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) t1,
    (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) t2,
    (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) t3;
"
docker exec lab18-primary mysql -uroot -prootpass appdb -e "SELECT COUNT(*) FROM orders;"

echo "[setup] stopping primary to safely corrupt a page's checksum at rest on disk..."
docker compose stop primary

TARGET_PATH="./data/mysql/appdb/orders.ibd"
if [ ! -f "$TARGET_PATH" ]; then
  echo "[setup] ERROR: expected tablespace file not found at $TARGET_PATH" >&2
  exit 1
fi
# Page 6 (0-indexed, 16384 bytes/page) — corrupt ONLY its 4-byte checksum
# field at the very start of the page. Every actual row byte on this
# page is left completely intact.
PAGE_OFFSET=$((6 * 16384))
echo "[setup] corrupting ${TARGET_PATH} checksum at byte offset ${PAGE_OFFSET} (4 bytes only)..."
dd if=/dev/urandom of="$TARGET_PATH" bs=1 seek="$PAGE_OFFSET" count=4 conv=notrunc status=none

echo "[setup] bringing primary back up (normal startup, no recovery flag)..."
docker compose start primary
for i in $(seq 1 40); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab18-primary 2>/dev/null || echo "starting")
  [ "$status" = "healthy" ] && break
  sleep 3
done

echo
echo "Done. The container reports healthy, but querying the corrupted table will crash mysqld:"
echo "  docker exec lab18-primary mysql -uroot -prootpass appdb -e \"SELECT COUNT(*) FROM orders;\""
echo "Check what actually happened:"
echo "  docker ps -a --filter name=lab18-primary"
echo "  docker logs lab18-primary 2>&1 | grep -i corrupt"
