#!/usr/bin/env bash
# Lab 31 (Replication Lag) reset — stops any active contention/challenge
# generators, brings the compose stack down and back up cleanly, waits for
# both instances to report healthy, then re-runs setup.sh to reconfigure
# replication and reintroduce the bounded I/O contention burst.
set -uo pipefail

cd "$(dirname "$0")"

echo "[reset] stopping any active contention generators on io-hog (best-effort)..."
docker exec lab31-io-hog pkill -9 dd 2>/dev/null || true
docker exec lab31-io-hog pkill -9 yes 2>/dev/null || true

echo "[reset] stopping any lingering long-running sessions on the standby (Challenge B, best-effort)..."
docker exec lab31-standby pkill -9 psql 2>/dev/null || true

echo "[reset] bringing the compose stack down..."
docker compose down -v

echo "[reset] bringing the compose stack back up..."
docker compose up -d

echo "[reset] waiting for primary and standby to report healthy..."
for svc in lab31-primary lab31-standby; do
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
