#!/usr/bin/env bash
# Lab 16 setup — a table with a TINYINT UNSIGNED AUTO_INCREMENT primary
# key (max value 255) gets hit with insert+delete churn. AUTO_INCREMENT
# never reuses a value even after the row that used it is deleted, so
# the counter burns through the column's entire range far faster than
# the actual row count would suggest.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab16-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[setup] lab16-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: lab16-primary never became healthy" >&2
    exit 1
  fi
done

echo "[setup] creating orders table with a TINYINT UNSIGNED primary key (max 255)..."
docker exec lab16-primary mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS orders;
  CREATE TABLE orders (
    id TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(20)
  );
"

echo "[setup] churning insert+delete batches (this burns through IDs without growing row count)..."
docker exec lab16-primary bash -c '
for batch in $(seq 1 24); do
  vals=""
  for i in $(seq 1 10); do
    vals="$vals,(\"order-$batch-$i\")"
  done
  vals="${vals#,}"
  mysql -uroot -prootpass appdb -e "INSERT INTO orders (data) VALUES $vals; DELETE FROM orders;" 2>/dev/null
done
'

echo "[setup] current state — note the counter vs. actual row count:"
docker exec lab16-primary mysql -uroot -prootpass appdb -e "SELECT COUNT(*) AS current_rows FROM orders;"
docker exec lab16-primary mysql -uroot -prootpass appdb -e "SHOW CREATE TABLE orders\G" | grep AUTO_INCREMENT

echo
echo "Done. The table is nearly empty but the counter is close to 255. Push it over:"
echo "  for i in \$(seq 1 20); do docker exec lab16-primary mysql -uroot -prootpass appdb -e \"INSERT INTO orders (data) VALUES ('x');\"; done"
