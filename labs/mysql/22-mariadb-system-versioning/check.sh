#!/usr/bin/env bash
# Lab 22 check - verifies the accounts table's actual (all-versions)
# row count is under control, not silently accumulating one row per
# historical UPDATE/DELETE forever.
set -uo pipefail

THRESHOLD=20  # a handful of recent versions is fine; hundreds is not

if ! docker exec lab22-primary mariadb-admin ping -h localhost -uroot -prootpass >/dev/null 2>&1; then
    echo "[FAIL] lab22-primary is not reachable - run setup.sh first"
    exit 1
fi

CURRENT=$(docker exec lab22-primary mariadb -uroot -prootpass appdb -N -e "SELECT COUNT(*) FROM accounts;")
ALL_VERSIONS=$(docker exec lab22-primary mariadb -uroot -prootpass appdb -N -e "SELECT COUNT(*) FROM accounts FOR SYSTEM_TIME ALL;")

echo "[check] current (visible) rows: $CURRENT"
echo "[check] all historical versions on disk: $ALL_VERSIONS"

if [ "$ALL_VERSIONS" -le "$THRESHOLD" ]; then
    echo "[PASS] history is under control (${ALL_VERSIONS} total versions, threshold ${THRESHOLD})."
    exit 0
else
    echo "[FAIL] ${ALL_VERSIONS} total row versions on disk - history is accumulating unbounded."
    exit 1
fi
