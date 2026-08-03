#!/usr/bin/env bash
# Lab 34 setup — a btree index bloats from repeated random-value updates
# even though the underlying table's row count never changes.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab34-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[setup] lab34-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: lab34-primary never became healthy, check 'docker logs lab34-primary'"
    exit 1
  fi
done

echo "[setup] creating pgstattuple extension and widgets table+index..."
docker exec lab34-primary psql -U postgres -d appdb -c "
  CREATE EXTENSION IF NOT EXISTS pgstattuple;
  DROP TABLE IF EXISTS widgets;
  CREATE TABLE widgets (id SERIAL PRIMARY KEY, sku TEXT);
  CREATE INDEX idx_widgets_sku ON widgets (sku);
  INSERT INTO widgets (sku) SELECT 'SKU-' || g FROM generate_series(1, 50000) g;
"

echo "[setup] running a bounded workload: 30 rounds of full-table random-value UPDATEs on the indexed column..."
echo "[setup] (no VACUUM between rounds on purpose — dead index entries pile up across scattered pages)"
docker exec lab34-primary bash -c '
  for i in $(seq 1 30); do
    psql -U postgres -d appdb -c "UPDATE widgets SET sku = '"'"'SKU-'"'"' || (random()*1000000)::int;" >/dev/null
  done
'

echo "[setup] running a plain VACUUM (marks dead entries reusable, does NOT shrink the index file)..."
docker exec lab34-primary psql -U postgres -d appdb -c "VACUUM widgets;"

echo "[setup] done. Index bloat state (pgstattuple's pgstatindex):"
docker exec lab34-primary psql -U postgres -d appdb -c "
  SELECT version, tree_level, index_size, avg_leaf_density
  FROM pgstatindex('idx_widgets_sku');
"
echo "[setup] compare against table row count (should be unchanged at 50000):"
docker exec lab34-primary psql -U postgres -d appdb -c "SELECT count(*) FROM widgets;"
