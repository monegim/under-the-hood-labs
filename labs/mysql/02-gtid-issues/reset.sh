#!/usr/bin/env bash
# Lab 2 (GTID Errant Transaction) reset — tears the compose stack down
# (including volumes, so old GTID/binlog state doesn't leak into the next
# run) and re-runs setup.sh to reproduce the errant-transaction incident.
set -uo pipefail

cd "$(dirname "$0")"

echo "[reset] bringing the compose stack down (including volumes)..."
docker compose down -v

echo "[reset] bringing the compose stack back up..."
docker compose up -d

echo "[reset] waiting for primary and replica to report healthy..."
for svc in lab02-primary lab02-replica; do
  ready=0
  for i in $(seq 1 60); do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$svc" 2>/dev/null || echo "starting")
    if [ "$status" = "healthy" ]; then
      echo "[reset] $svc is healthy"
      ready=1
      break
    fi
    sleep 3
  done
  if [ "$ready" -ne 1 ]; then
    echo "[reset] ERROR: $svc never became healthy, check 'docker logs $svc'"
    exit 1
  fi
done

echo "[reset] re-running setup.sh to reproduce the errant-transaction incident..."
./setup.sh

echo "[reset] done. Run ./check.sh to verify health."
