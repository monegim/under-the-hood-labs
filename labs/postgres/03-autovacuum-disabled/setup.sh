#!/usr/bin/env bash
# Lab 33 setup — a table with autovacuum_enabled = false silently
# accumulates dead tuples because nothing is ever cleaning them up.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab33-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[setup] lab33-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: lab33-primary never became healthy, check 'docker logs lab33-primary'"
    exit 1
  fi
done

echo "[setup] creating accounts table with autovacuum disabled..."
docker exec lab33-primary psql -U postgres -d appdb -c "
  DROP TABLE IF EXISTS accounts;
  CREATE TABLE accounts (
    id SERIAL PRIMARY KEY,
    balance NUMERIC NOT NULL DEFAULT 1000,
    updated_at TIMESTAMPTZ DEFAULT now()
  ) WITH (autovacuum_enabled = false);
  INSERT INTO accounts (balance) SELECT 1000 FROM generate_series(1, 2000);
"

echo "[setup] running a bounded UPDATE workload (50 full-table rewrites) — autovacuum will never clean up after these:"
docker exec lab33-primary bash -c '
  for i in $(seq 1 50); do
    psql -U postgres -d appdb -c "UPDATE accounts SET balance = balance + 1, updated_at = now();" >/dev/null
  done
'

echo "[setup] done. Dead tuple state:"
docker exec lab33-primary psql -U postgres -d appdb -c "
  SELECT relname, n_live_tup, n_dead_tup, last_autovacuum, last_vacuum
  FROM pg_stat_user_tables WHERE relname = 'accounts';
"
echo "[setup] and physical size for comparison:"
docker exec lab33-primary psql -U postgres -d appdb -c "
  SELECT pg_size_pretty(pg_total_relation_size('accounts'));
"
