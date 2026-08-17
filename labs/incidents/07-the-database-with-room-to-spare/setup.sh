#!/usr/bin/env bash
# Incident 07 setup - builds the entire broken environment:
#   postgres        - Postgres 16, PGDATA on a shared, inode-limited
#                      volume (tmpfs with a small nr_inodes ceiling -
#                      portable, no privileged loopback ext4 needed).
#   app             - a signup-service (POST /signup, GET /health)
#                      doing a plain INSERT + COMMIT per request.
#   request-logger  - an unrelated container writing one small file per
#                      "request" into a subdirectory of the SAME shared
#                      volume. Nothing in the page mentions it, and it
#                      never opens a single Postgres file.
#
# By the time this script finishes, request-logger has already
# exhausted every inode on the shared volume, and enough real signup
# traffic has been driven through the app to prove new signups are
# actually failing - the incident is live, same as walking onto a real
# page, not something you have to trust will eventually happen.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[1/5] Building and starting postgres, app, request-logger..."
docker compose up -d --build

echo "[2/5] Waiting for Postgres to report healthy..."
for i in $(seq 1 30); do
    status=$(docker inspect --format='{{.State.Health.Status}}' incident07-postgres 2>/dev/null || echo "starting")
    [ "$status" = "healthy" ] && break
    sleep 2
done

echo "[3/5] Waiting for the app to answer /health..."
for i in $(seq 1 30); do
    curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health 2>/dev/null | grep -q 200 && break
    sleep 2
done

echo "[4/5] Waiting for request-logger to exhaust the shared volume's inodes..."
for i in $(seq 1 60); do
    ifree=$(docker exec incident07-postgres df -i /data | awk 'NR==2{print $4}')
    if [ "$ifree" = "0" ]; then
        echo "      inodes exhausted."
        break
    fi
    sleep 2
    if [ "$i" -eq 60 ]; then
        echo "ERROR: inodes never exhausted - is request-logger running?" >&2
        exit 1
    fi
done

echo "[5/5] Driving real signup traffic until a write actually fails..."
BROKEN=0
for i in $(seq 1 400); do
    code=$(curl -s -o /tmp/incident07-setup-resp.json -w '%{http_code}' \
        -X POST http://localhost:8080/signup \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"user$i@example.com\"}" 2>/dev/null || echo "000")
    if [ "$code" = "500" ]; then
        BROKEN=1
        echo "      signup #$i failed: $(cat /tmp/incident07-setup-resp.json 2>/dev/null)"
        break
    fi
done
rm -f /tmp/incident07-setup-resp.json

if [ "$BROKEN" -ne 1 ]; then
    echo "ERROR: drove 400 signups and none failed - incident did not reproduce" >&2
    exit 1
fi

echo
echo "Done. Environment is up and the incident is already in progress."
echo "  App:      http://localhost:8080"
echo "  Postgres: localhost:5470 (appuser/apppass)"
echo
echo "Try:"
echo '  curl -s -X POST http://localhost:8080/signup -H "Content-Type: application/json" -d "{\"email\":\"new-user@example.com\"}"'
