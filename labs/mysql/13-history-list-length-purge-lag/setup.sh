#!/usr/bin/env bash
# Lab 13 setup — a long-running transaction holds InnoDB's purge view
# back while a hot row gets churned heavily, growing the undo History
# List Length unbounded — the MySQL/InnoDB analog of the Postgres
# transaction-ID-wraparound lab: a cleanup mechanism that runs
# continuously in the background, until something holds it back.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab13-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[setup] lab13-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: lab13-primary never became healthy" >&2
    exit 1
  fi
done

echo "[setup] creating the churn table and a churn_rows() helper procedure..."
docker exec lab13-primary mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS churn;
  CREATE TABLE churn (id INT PRIMARY KEY, val INT NOT NULL);
  INSERT INTO churn (id, val) VALUES (1, 0);
"
docker exec lab13-primary mysql -uroot -prootpass appdb -e "
  DROP PROCEDURE IF EXISTS churn_rows;
  DELIMITER //
  CREATE PROCEDURE churn_rows(n INT)
  BEGIN
    DECLARE i INT DEFAULT 0;
    WHILE i < n DO
      UPDATE churn SET val = val + 1 WHERE id = 1;
      SET i = i + 1;
    END WHILE;
  END //
  DELIMITER ;
"

echo "[setup] starting a long-running transaction against 'churn' (bounded at 300s, self-terminating)..."
docker exec -d lab13-primary mysql -uroot -prootpass appdb -e "
  BEGIN;
  SELECT * FROM churn;
  DO SLEEP(300);
  COMMIT;
"
sleep 2

echo "[setup] churning the hot row 5000 times while the transaction above stays open..."
docker exec lab13-primary mysql -uroot -prootpass appdb -e "CALL churn_rows(5000);"

echo
echo "Done. Check the current History List Length:"
echo "  docker exec lab13-primary mysql -uroot -prootpass -e \"SHOW ENGINE INNODB STATUS\\\\G\" | grep 'History list length'"
echo "Find what's holding it back:"
echo "  docker exec lab13-primary mysql -uroot -prootpass -e \"SELECT trx_id, trx_started, trx_mysql_thread_id, trx_query FROM information_schema.innodb_trx;\""
