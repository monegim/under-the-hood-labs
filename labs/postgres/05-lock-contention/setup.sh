#!/usr/bin/env bash
# Lab 35 setup — a session left idle in an open transaction holds a row
# lock and blocks everything else that touches the same row.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab35-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[setup] lab35-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: lab35-primary never became healthy, check 'docker logs lab35-primary'"
    exit 1
  fi
done

echo "[setup] creating accounts table..."
docker exec lab35-primary psql -U postgres -d appdb -c "
  DROP TABLE IF EXISTS accounts;
  CREATE TABLE accounts (id SERIAL PRIMARY KEY, name TEXT, balance NUMERIC NOT NULL DEFAULT 1000);
  INSERT INTO accounts (name, balance) VALUES ('alice', 1000), ('bob', 1000), ('carol', 1000);
"

echo "[setup] starting a session that opens a transaction, updates account 1, then sits idle without committing..."
echo "[setup] (bounded: self-commits after 5 minutes if nobody intervenes first)"
docker exec -d lab35-primary bash -c '
  psql -U postgres -d appdb -c "
    BEGIN;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    SELECT pg_sleep(300);
    COMMIT;
  "
'

sleep 2
echo "[setup] done. Confirm the idle-in-transaction session exists:"
docker exec lab35-primary psql -U postgres -c \
  "SELECT pid, state, now() - xact_start AS xact_age, query FROM pg_stat_activity WHERE state = 'idle in transaction';"
echo "[setup] try updating the same row from a fresh session — it will hang:"
echo "    docker exec lab35-primary psql -U postgres -d appdb -c \"UPDATE accounts SET balance = balance + 50 WHERE id = 1;\""
