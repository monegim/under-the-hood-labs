#!/usr/bin/env bash
# Lab 1 (Replication Lag / I/O Contention) — stops the noisy-neighbor
# generators, brings the compose stack down and back up cleanly, waits for
# both instances to report healthy, then re-runs setup.sh to reconfigure
# replication and reintroduce the bounded I/O contention burst.
set -uo pipefail

cd "$(dirname "$0")"

echo "[reset] stopping any active contention generators on io-hog (best-effort, ignored if not running)..."
docker exec lab30-io-hog pkill -9 dd 2>/dev/null || true
docker exec lab30-io-hog pkill -9 yes 2>/dev/null || true

echo "[reset] bringing the compose stack down..."
docker compose down -v

echo "[reset] bringing the compose stack back up..."
docker compose up -d

echo "[reset] waiting for primary and replica to report healthy..."
for svc in lab30-primary lab30-replica; do
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

echo "[reset] re-running setup.sh to reconfigure replication and reintroduce I/O contention..."
./setup.sh

echo "[reset] done. Run ./check.sh to verify health."
