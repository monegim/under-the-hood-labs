#!/usr/bin/env bash
# Lab 23 check - the actual business-facing symptom: does a routine
# restart create a gap in invoice numbers? Issues a value, restarts
# MariaDB for real, issues another value, and requires them to be
# consecutive (or at least a small, bounded gap) - not the
# hundred-wide gap CACHE 100 produces on every single restart.
set -uo pipefail

MAX_GAP=5

if ! docker exec lab23-primary mariadb-admin ping -h localhost -uroot -prootpass >/dev/null 2>&1; then
    echo "[FAIL] lab23-primary is not reachable - run setup.sh first"
    exit 1
fi

BEFORE=$(docker exec lab23-primary mariadb -uroot -prootpass appdb -N -e "SELECT NEXTVAL(invoice_seq);")
echo "[check] issued value before restart: $BEFORE"

echo "[check] restarting MariaDB (a real, ordinary restart)..."
docker compose -f "$(dirname "${BASH_SOURCE[0]}")/docker-compose.yml" restart primary >/dev/null
for i in $(seq 1 60); do
    status=$(docker inspect --format='{{.State.Health.Status}}' lab23-primary 2>/dev/null || echo "starting")
    [ "$status" = "healthy" ] && break
    sleep 2
done

AFTER=$(docker exec lab23-primary mariadb -uroot -prootpass appdb -N -e "SELECT NEXTVAL(invoice_seq);")
echo "[check] issued value after restart: $AFTER"

GAP=$((AFTER - BEFORE - 1))
echo "[check] gap between the two: $GAP"

if [ "$GAP" -le "$MAX_GAP" ]; then
    echo "[PASS] gap is $GAP (at or below $MAX_GAP) - a routine restart no longer burns a huge block of invoice numbers."
    exit 0
else
    echo "[FAIL] gap is $GAP - a routine restart is still burning a large block of invoice numbers."
    exit 1
fi
