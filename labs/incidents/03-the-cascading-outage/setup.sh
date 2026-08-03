#!/usr/bin/env bash
# Incident 03 setup - builds the entire broken environment:
#   auth   - leaks one file descriptor per /validate call, capped at a
#            tiny nofile ulimit (50)
#   orders - calls auth's /validate on every request; has no bug of its
#            own
#
# setup.sh pre-exhausts auth's file descriptor budget by hitting it
# directly ~80 times before you ever look at the environment, so
# orders is already failing by the time you start investigating -
# same as walking onto a live page.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[1/4] Building and starting auth, orders..."
docker compose up -d --build

echo "[2/4] Waiting for both services to answer /health..."
for svc in "8000" "8001"; do
    for i in $(seq 1 30); do
        curl -s -o /dev/null -w '%{http_code}' "http://localhost:${svc}/health" 2>/dev/null | grep -q 200 && break
        sleep 2
    done
done

echo "[3/4] Driving normal-looking traffic through auth to exhaust its file descriptors..."
for i in $(seq 1 80); do
    curl -s -o /dev/null -X POST http://localhost:8000/validate || true
done

echo "[4/4] Confirming the incident is live (orders should now be failing)..."
sleep 1
curl -s http://localhost:8001/orders/123 || true

echo
echo
echo "Done. The incident is already in progress."
echo "  orders:  http://localhost:8001"
echo "  auth:    http://localhost:8000"
echo
echo "Try:"
echo "  curl -s http://localhost:8001/orders/123"
