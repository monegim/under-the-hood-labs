#!/usr/bin/env bash
# Lab 33 (Autovacuum Disabled) reset — brings the compose stack down and
# back up cleanly (also undoes any autovacuum_max_workers / scale_factor
# changes from the challenges, since those live in the container's config
# state which gets wiped by -v), waits for health, then re-runs setup.sh.
set -uo pipefail

cd "$(dirname "$0")"

echo "[reset] bringing the compose stack down..."
docker compose down -v

echo "[reset] bringing the compose stack back up..."
docker compose up -d

echo "[reset] waiting for primary to report healthy..."
ready=0
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab33-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[reset] lab33-primary is healthy"
    ready=1
    break
  fi
  sleep 3
done
if [ "$ready" -ne 1 ]; then
  echo "[reset] ERROR: lab33-primary never became healthy, check 'docker logs lab33-primary'"
  exit 1
fi

echo "[reset] re-running setup.sh to recreate the disabled-autovacuum incident..."
./setup.sh

echo "[reset] done. Run ./check.sh to verify health."
