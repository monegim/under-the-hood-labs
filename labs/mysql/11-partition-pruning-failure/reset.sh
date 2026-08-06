#!/usr/bin/env bash
# Lab 11 (Partition Pruning Failure) reset — brings the compose stack down
# and back up cleanly, then re-runs setup.sh to rebuild the partitioned
# table and repopulate it.
set -uo pipefail

cd "$(dirname "$0")"

echo "[reset] bringing the compose stack down..."
docker compose down -v

echo "[reset] bringing the compose stack back up..."
docker compose up -d

echo "[reset] waiting for primary to report healthy..."
ready=0
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab11-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[reset] lab11-primary is healthy"
    ready=1
    break
  fi
  sleep 3
done
if [ "$ready" -ne 1 ]; then
  echo "[reset] ERROR: lab11-primary never became healthy, check 'docker logs lab11-primary'"
  exit 1
fi

echo "[reset] re-running setup.sh to rebuild the partitioned table..."
./setup.sh

echo "[reset] done. Run ./check.sh to verify health."
