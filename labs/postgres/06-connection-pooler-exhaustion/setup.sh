#!/usr/bin/env bash
# Lab 06 setup — PgBouncer in transaction-pooling mode with
# default_pool_size=5 sitting in front of Postgres, which itself allows
# up to 100 connections. 8 clients open a transaction through PgBouncer
# and hold it (pg_sleep), each occupying one of the 5 pooled backend
# connections for the duration — enough to exceed the pool, so new
# clients start queuing, even though Postgres itself has 95 connections
# of headroom nobody is using.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary + pgbouncer..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' pglab6-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[setup] pglab6-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: pglab6-primary never became healthy" >&2
    exit 1
  fi
done

echo "[setup] waiting for pgbouncer to accept connections..."
for i in $(seq 1 30); do
  if docker exec -e PGPASSWORD=postgres pglab6-pgbouncer psql -h 127.0.0.1 -p 5432 -U postgres -d appdb -c "SELECT 1;" >/dev/null 2>&1; then
    echo "[setup] pgbouncer is up"
    break
  fi
  sleep 2
  if [ "$i" -eq 30 ]; then
    echo "[setup] ERROR: pgbouncer never came up, check 'docker logs pglab6-pgbouncer'" >&2
    exit 1
  fi
done

echo "[setup] creating a test table..."
docker exec pglab6-primary psql -U postgres -d appdb -c "
  DROP TABLE IF EXISTS widgets;
  CREATE TABLE widgets (id SERIAL PRIMARY KEY, name TEXT);
"

echo "[setup] launching 8 clients through PgBouncer, each holding a 60s transaction..."
echo "[setup] (pool default_pool_size=5 — the 6th, 7th, 8th will queue)"
for i in $(seq 1 8); do
  docker exec -i pglab6-pgbouncer sh -c "cat > /tmp/client-$i.sql" <<SQL
BEGIN;
INSERT INTO widgets (name) VALUES ('client-$i');
SELECT pg_sleep(60);
COMMIT;
SQL
  docker exec -d -e PGPASSWORD=postgres pglab6-pgbouncer sh -c \
    "psql -h 127.0.0.1 -p 5432 -U postgres -d appdb -f /tmp/client-$i.sql > /tmp/client-$i.log 2>&1"
done

sleep 3
echo "[setup] done. Check pool state:"
echo "  docker exec -e PGPASSWORD=postgres pglab6-pgbouncer psql -h 127.0.0.1 -p 5432 -U postgres -d pgbouncer -c 'SHOW POOLS;'"
