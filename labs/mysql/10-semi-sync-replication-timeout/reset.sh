#!/usr/bin/env bash
# Lab 10 (Semi-Sync Replication Timeout) reset — unpauses anything left
# paused, removes the optional Challenge B second replica if present,
# brings the compose stack down and back up cleanly, then re-runs
# setup.sh to reconfigure semi-sync replication from scratch.
set -uo pipefail

cd "$(dirname "$0")"

echo "[reset] unpausing any paused containers (best-effort)..."
docker unpause lab10-replica 2>/dev/null || true
docker unpause lab10-replica2 2>/dev/null || true

echo "[reset] removing Challenge B's second replica if it exists..."
docker rm -f lab10-replica2 2>/dev/null || true

echo "[reset] bringing the compose stack down..."
docker compose down -v

echo "[reset] bringing the compose stack back up..."
docker compose up -d

echo "[reset] waiting for primary and replica to report healthy..."
for svc in lab10-primary lab10-replica; do
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

echo "[reset] re-running setup.sh to reconfigure semi-sync replication..."
./setup.sh

echo "[reset] done. Run ./check.sh to verify health."
