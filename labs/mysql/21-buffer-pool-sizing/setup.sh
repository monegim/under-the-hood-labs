#!/usr/bin/env bash
# Lab 21 setup - builds a single MySQL instance with a deliberately
# small InnoDB buffer pool (24MB - representing a setting nobody's
# revisited since the app was small) and a `working_set` table that
# has since grown to ~75MB - comfortably too big to fully fit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[setup] starting MySQL with a 24MB buffer pool..."
docker compose up -d

echo "[setup] waiting for MySQL to report healthy..."
for i in $(seq 1 60); do
    status=$(docker inspect --format='{{.State.Health.Status}}' lab21-primary 2>/dev/null || echo "starting")
    [ "$status" = "healthy" ] && break
    sleep 2
    if [ "$i" -eq 60 ]; then
        echo "[setup] ERROR: lab21-primary never became healthy" >&2
        exit 1
    fi
done

echo "[setup] building working_set (grows to ~75MB via repeated doubling)..."
docker exec lab21-primary mysql -uroot -prootpass appdb -e "
CREATE TABLE IF NOT EXISTS working_set (
  id INT PRIMARY KEY AUTO_INCREMENT,
  val VARCHAR(200)
) ENGINE=InnoDB;
INSERT INTO working_set (val)
SELECT LPAD(CONCAT('row-', n), 200, 'x') FROM (
  SELECT a.N + b.N*10 + c.N*100 + d.N*1000 + e.N*10000 AS n
  FROM (SELECT 0 N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) a,
       (SELECT 0 N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) b,
       (SELECT 0 N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) c,
       (SELECT 0 N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) d,
       (SELECT 0 N UNION SELECT 1) e
) nums;
"
for i in 1 2 3 4; do
    docker exec lab21-primary mysql -uroot -prootpass appdb -e "INSERT INTO working_set (val) SELECT val FROM working_set;"
done
docker exec lab21-primary mysql -uroot -prootpass appdb -e "ANALYZE TABLE working_set;"

echo "[setup] warming the buffer pool with realistic random-lookup traffic..."
for i in 1 2 3; do
    docker exec lab21-primary bash -c "
    for j in \$(seq 1 2000); do
      echo \"SELECT val FROM working_set WHERE id = \$(( (RANDOM * RANDOM * RANDOM) % 320000 + 1 ));\"
    done | mysql -uroot -prootpass appdb -N
    " >/dev/null
done

ROWS=$(docker exec lab21-primary mysql -uroot -prootpass appdb -N -e "SELECT COUNT(*) FROM working_set;")
SIZE=$(docker exec lab21-primary mysql -uroot -prootpass -N -e "SELECT ROUND((data_length+index_length)/1024/1024,1) FROM information_schema.tables WHERE table_schema='appdb' AND table_name='working_set';")
POOL=$(docker exec lab21-primary mysql -uroot -prootpass -N -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" | awk '{printf "%.1f", $2/1024/1024}')

echo
echo "Done. working_set: ${ROWS} rows, ~${SIZE}MB. innodb_buffer_pool_size: ~${POOL}MB."
echo "Try:"
echo "  docker exec lab21-primary mysql -uroot -prootpass -e \"SHOW STATUS LIKE 'Innodb_buffer_pool_reads';\""
echo "  docker exec lab21-primary mysql -uroot -prootpass -e \"SHOW STATUS LIKE 'Innodb_buffer_pool_read_requests';\""
