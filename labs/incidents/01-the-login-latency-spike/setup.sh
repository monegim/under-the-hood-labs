#!/usr/bin/env bash
# Incident 01 setup - builds the entire broken environment:
#   mysql  - MySQL 8.0, max_connections deliberately capped at 30
#   app    - the login service (Flask + a normal-looking connection pool)
#   worker - the "loyalty-points-reconciler" background job that holds
#            ~26 of those 30 connections open at all times
#
# By the time this script finishes, the incident is already live - new
# login requests are already queuing/failing, same as walking onto a
# real page in progress.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[1/4] Building and starting mysql, app, worker..."
docker compose up -d --build

echo "[2/4] Waiting for MySQL to report healthy..."
for i in $(seq 1 30); do
    status=$(docker inspect --format='{{.State.Health.Status}}' incident01-mysql 2>/dev/null || echo "starting")
    if [ "$status" = "healthy" ]; then
        break
    fi
    sleep 2
done

echo "[3/4] Waiting for the login service to answer /health..."
for i in $(seq 1 30); do
    if curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health 2>/dev/null | grep -q 200; then
        break
    fi
    sleep 2
done

echo "[4/4] Confirming the reconciler worker is running..."
sleep 3
docker logs incident01-worker 2>&1 | tail -5

echo
echo "Done. Environment is up and the incident is already in progress."
echo "  App:   http://localhost:8080"
echo "  MySQL: localhost:3306 (root/rootpass)"
echo
echo "Try:"
echo '  curl -s -X POST http://localhost:8080/login -H "Content-Type: application/json" -d "{\"username\":\"demo\",\"password\":\"demopass\"}" -w "\ntime_total: %{time_total}s\n"'
