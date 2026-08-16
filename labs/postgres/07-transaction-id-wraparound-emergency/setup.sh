#!/usr/bin/env bash
# Lab 07 setup — a table accumulates transaction ID "age" as the global
# XID counter advances, eventually crossing autovacuum_freeze_max_age
# (set to Postgres's actual hard minimum, 100000, here — the real default
# is 200,000,000 — so this is reachable in a lab timeframe; see
# CONCEPTS.md for why this is an honest simulation of the real mechanism,
# not a shortcut around it). Past that threshold, an anti-wraparound
# autovacuum SHOULD run automatically — except autovacuum is disabled
# server-wide here, which is the actual point of this lab.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary (autovacuum off, autovacuum_freeze_max_age=100000)..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' pglab7-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[setup] pglab7-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: pglab7-primary never became healthy" >&2
    exit 1
  fi
done

echo "[setup] creating a table (autovacuum is OFF server-wide — see docker-compose.yml)..."
docker exec pglab7-primary psql -U postgres -d appdb -c "
  DROP TABLE IF EXISTS counters;
  CREATE TABLE counters (id INT PRIMARY KEY, val INT NOT NULL DEFAULT 0);
  INSERT INTO counters (id, val) VALUES (1, 0);
"

echo "[setup] recording the starting age(relfrozenxid) for counters..."
docker exec pglab7-primary psql -U postgres -d appdb -c \
  "SELECT relname, age(relfrozenxid) FROM pg_class WHERE relname = 'counters';"

echo "[setup] burning ~110,000 transactions against the table (takes well under a minute)..."
# CREATE PROCEDURE and CALL must be separate -c invocations: psql sends a
# multi-statement -c string as one implicit transaction block, and COMMIT
# inside a procedure is only legal when the CALL itself is top-level (not
# already inside a transaction block) — combining them fails with
# "invalid transaction termination".
docker exec pglab7-primary psql -U postgres -d appdb -c "
  CREATE OR REPLACE PROCEDURE burn_xids(n INT) LANGUAGE plpgsql AS \$\$
  BEGIN
    FOR i IN 1..n LOOP
      UPDATE counters SET val = val + 1 WHERE id = 1;
      COMMIT;
    END LOOP;
  END;
  \$\$;
"
docker exec pglab7-primary psql -U postgres -d appdb -c "CALL burn_xids(110000);"

echo
echo "Done. Check the current age — it should now be past the 100000 threshold:"
echo "  docker exec pglab7-primary psql -U postgres -d appdb -c \"SELECT relname, age(relfrozenxid) FROM pg_class WHERE relname = 'counters';\""
echo "With autovacuum off, nothing will bring that number back down on its own."
