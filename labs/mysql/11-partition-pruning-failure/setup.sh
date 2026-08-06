#!/usr/bin/env bash
# Lab 11 setup — a RANGE-partitioned events table (by YEAR(created_at)),
# populated with rows spread across 4 years so each partition has a
# meaningfully different row count. The table itself is fine; the incident
# this lab is built around is entirely about QUERY PATTERNS that defeat
# MySQL's ability to prune partitions at plan time.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab11-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[setup] lab11-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: lab11-primary never became healthy, check 'docker logs lab11-primary'"
    exit 1
  fi
done

echo "[setup] creating a RANGE-partitioned events table (partitioned by YEAR(created_at))..."
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS events;
  CREATE TABLE events (
    id BIGINT AUTO_INCREMENT,
    created_at DATE NOT NULL,
    customer_id INT NOT NULL,
    payload VARCHAR(500),
    PRIMARY KEY (id, created_at)
  )
  PARTITION BY RANGE (YEAR(created_at)) (
    PARTITION p2021 VALUES LESS THAN (2022),
    PARTITION p2022 VALUES LESS THAN (2023),
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
  );
"

echo "[setup] populating ~20,000 rows spread across 2021-2024 (recursive CTE, raising cte_max_recursion_depth for it)..."
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  SET cte_max_recursion_depth = 100000;
  INSERT INTO events (created_at, customer_id, payload)
  WITH RECURSIVE seq AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 20000
  )
  SELECT
    DATE_ADD('2021-01-01', INTERVAL FLOOR(RAND() * 1460) DAY),
    FLOOR(RAND() * 1000) + 1,
    REPEAT('x', 50)
  FROM seq;
"

echo "[setup] row counts per partition:"
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  SELECT PARTITION_NAME, TABLE_ROWS
  FROM information_schema.PARTITIONS
  WHERE TABLE_SCHEMA = 'appdb' AND TABLE_NAME = 'events'
  ORDER BY PARTITION_ORDINAL_POSITION;
"

echo "[setup] creating an unpartitioned order_items table for the JOIN challenge..."
docker exec lab11-primary mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS order_items;
  CREATE TABLE order_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_id BIGINT NOT NULL,
    sku VARCHAR(50)
  );
  INSERT INTO order_items (event_id, sku)
  SELECT id, CONCAT('SKU-', FLOOR(RAND()*50)) FROM events WHERE RAND() < 0.3;
"

echo "[setup] done. Start diagnosing with EXPLAIN — see README Step 2."
