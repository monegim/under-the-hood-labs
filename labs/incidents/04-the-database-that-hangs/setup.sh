#!/usr/bin/env bash
# Incident 04 setup - builds the entire broken environment:
#   mysql       - MySQL 8.0, default durable-commit settings
#                 (innodb_flush_log_at_trx_commit=1 - fsync on every COMMIT)
#   app         - a save-service doing a plain INSERT + COMMIT per request
#   backup-job  - an unrelated container doing heavy synchronous writes
#                 (dd ... conv=fdatasync) to a directory that shares the
#                 SAME underlying host disk as MySQL's datadir
#
# By the time this script finishes, backup-job is already hammering the
# shared disk and every /save call is already slow - the incident is
# live, same as walking onto a real page.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[1/4] Preparing host directories (mysql datadir + backup scratch, siblings on the same disk)..."
mkdir -p ./data/disk/mysql ./data/disk/backup-scratch

echo "[2/4] Building and starting mysql, app, backup-job..."
docker compose up -d --build

echo "[3/4] Waiting for MySQL to report healthy..."
for i in $(seq 1 30); do
    status=$(docker inspect --format='{{.State.Health.Status}}' incident04-mysql 2>/dev/null || echo "starting")
    [ "$status" = "healthy" ] && break
    sleep 2
done

echo "[4/4] Waiting for the app to answer /health..."
for i in $(seq 1 30); do
    curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health 2>/dev/null | grep -q 200 && break
    sleep 2
done

echo
echo "Confirming backup-job is generating disk I/O..."
sleep 3
docker logs incident04-backup-job 2>&1 | tail -5 || true

echo
echo "Done. Environment is up and the incident is already in progress."
echo "  App:   http://localhost:8080"
echo "  MySQL: localhost:3306 (root/rootpass)"
echo
echo "Try:"
echo '  curl -s -X POST http://localhost:8080/save -H "Content-Type: application/json" -d "{\"payload\":\"checkout-123\"}"'
