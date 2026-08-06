#!/usr/bin/env bash
# Lab 9 (InnoDB Redo Log Full) reset — brings the compose stack down and
# back up cleanly (restoring the tiny 8MB innodb_redo_log_capacity from
# docker-compose.yml), waits for it to report healthy, then re-runs
# setup.sh to rebuild the schema and re-run the write workload.
set -uo pipefail

cd "$(dirname "$0")"

echo "[reset] bringing the compose stack down..."
docker compose down -v

echo "[reset] bringing the compose stack back up..."
docker compose up -d

echo "[reset] waiting for primary to report healthy..."
ready=0
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab09-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[reset] lab09-primary is healthy"
    ready=1
    break
  fi
  sleep 3
done
if [ "$ready" -ne 1 ]; then
  echo "[reset] ERROR: lab09-primary never became healthy, check 'docker logs lab09-primary'"
  exit 1
fi

echo "[reset] re-running setup.sh to rebuild schema and reintroduce the write load..."
./setup.sh

echo "[reset] done. Run ./check.sh to verify health."
