#!/usr/bin/env bash
# Lab 08 setup — publisher/subscriber logical replication, then a direct
# write on the subscriber creates a primary-key row the publisher will
# later also try to insert, which halts the whole subscription.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up publisher and subscriber..."
docker compose up -d

for name in pglab8-publisher pglab8-subscriber; do
  echo "[setup] waiting for $name to report healthy..."
  for i in $(seq 1 60); do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || echo "starting")
    if [ "$status" = "healthy" ]; then
      echo "[setup] $name is healthy"
      break
    fi
    sleep 3
    if [ "$i" -eq 60 ]; then
      echo "[setup] ERROR: $name never became healthy" >&2
      exit 1
    fi
  done
done

echo "[setup] creating the orders table on both sides..."
for name in pglab8-publisher pglab8-subscriber; do
  docker exec "$name" psql -U postgres -d appdb -c "
    DROP TABLE IF EXISTS orders;
    CREATE TABLE orders (id INT PRIMARY KEY, item TEXT NOT NULL);
  "
done

echo "[setup] seeding the publisher with a few rows..."
docker exec pglab8-publisher psql -U postgres -d appdb -c "
  INSERT INTO orders (id, item) VALUES (1, 'widget'), (2, 'gadget');
"

echo "[setup] creating the publication on the publisher..."
docker exec pglab8-publisher psql -U postgres -d appdb -c "
  CREATE PUBLICATION orders_pub FOR TABLE orders;
"

echo "[setup] creating the subscription on the subscriber..."
docker exec pglab8-subscriber psql -U postgres -d appdb -c "
  CREATE SUBSCRIPTION orders_sub
    CONNECTION 'host=publisher port=5432 dbname=appdb user=postgres password=postgres'
    PUBLICATION orders_pub;
"

echo "[setup] waiting for the initial sync to catch up..."
sleep 5
docker exec pglab8-subscriber psql -U postgres -d appdb -c "SELECT * FROM orders ORDER BY id;"

echo "[setup] inserting a conflicting row directly on the subscriber (id=3)..."
docker exec pglab8-subscriber psql -U postgres -d appdb -c "
  INSERT INTO orders (id, item) VALUES (3, 'subscriber-local-item');
"

echo "[setup] now inserting the SAME id on the publisher — this row will replicate and conflict..."
docker exec pglab8-publisher psql -U postgres -d appdb -c "
  INSERT INTO orders (id, item) VALUES (3, 'publisher-item');
"

echo "[setup] inserting one more, non-conflicting row on the publisher (id=4)..."
docker exec pglab8-publisher psql -U postgres -d appdb -c "
  INSERT INTO orders (id, item) VALUES (4, 'placed-after-the-conflict');
"

echo
echo "Done. Give replication a few seconds to hit the conflict, then check:"
echo "  docker exec pglab8-subscriber psql -U postgres -d appdb -c \"SELECT * FROM pg_stat_subscription;\""
echo "  docker logs pglab8-subscriber 2>&1 | grep -i 'duplicate key' | tail -5"
echo "Notice id=4 never shows up on the subscriber either — it's queued behind the stuck conflict."
