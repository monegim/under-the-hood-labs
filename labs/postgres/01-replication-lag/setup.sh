#!/usr/bin/env bash
# Lab 31 setup — Postgres primary/standby streaming replication, where
# replay lag spikes because something else on the standby's HOST is
# starving the disk the standby's PGDATA lives on.
#
# Safety note: every generator in this script is BOUNDED (fixed iteration
# counts / fixed durations), not an infinite loop. To trigger another
# burst of contention after this script finishes, see README "Re-triggering
# contention".
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary, standby, io-hog..."
docker compose up -d

echo "[setup] waiting for primary and standby to report healthy..."
for svc in lab31-primary lab31-standby; do
  for i in $(seq 1 60); do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$svc" 2>/dev/null || echo "starting")
    if [ "$status" = "healthy" ]; then
      echo "[setup] $svc is healthy"
      break
    fi
    sleep 3
    if [ "$i" -eq 60 ]; then
      echo "[setup] ERROR: $svc never became healthy, check 'docker logs $svc'"
      exit 1
    fi
  done
done

echo "[setup] replication status on primary:"
docker exec lab31-primary psql -U postgres -c \
  "SELECT client_addr, state, sent_lsn, replay_lsn FROM pg_stat_replication;"

echo "[setup] creating schema on primary..."
docker exec lab31-primary psql -U postgres -d appdb -c "
  CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
  );
"

echo "[setup] starting a bounded write workload against primary (background, ~3 min, self-terminating)..."
docker exec -d lab31-primary bash -c '
  for i in $(seq 1 300); do
    psql -U postgres -d appdb -c "
      INSERT INTO orders (data)
      SELECT repeat(chr(65 + (random()*25)::int), 200) FROM generate_series(1,50);
    " >/dev/null 2>&1
    sleep 0.5
  done
'

echo "[setup] starting bounded I/O contention on the standby host disk (background, self-terminating)..."
echo "[setup] 4 parallel writers x 40 iterations x 128MB, overwriting the SAME 4 files"
echo "[setup] (bounded disk usage, ~512MB resident, large total I/O throughput)"
docker exec -d lab31-io-hog bash -c '
  for w in 1 2 3 4; do
    (
      for i in $(seq 1 40); do
        dd if=/dev/zero of=/hogdata/hog-$w.dat bs=1M count=128 conv=fdatasync 2>/dev/null
      done
    ) &
  done
  wait
'

echo "[setup] done. Both background generators are running and will finish on their own"
echo "[setup] (writer: ~3 minutes, io-hog: until all 4 workers finish their 40 iterations)."
echo "[setup] Start diagnosing now:"
echo "    docker exec lab31-primary psql -U postgres -c \"SELECT client_addr, state, replay_lag FROM pg_stat_replication;\""
