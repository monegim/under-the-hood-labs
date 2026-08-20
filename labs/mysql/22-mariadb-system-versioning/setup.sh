#!/usr/bin/env bash
# Lab 22 setup - builds a MariaDB instance with a system-versioned
# table and simulates months of ordinary application traffic against
# it: routine balance updates, nothing unusual. By the time this
# finishes, the table's *visible* row count is tiny, but its actual
# on-disk row count - every historical version MariaDB has been
# quietly keeping since the table was created - is not.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[setup] starting MariaDB..."
docker compose up -d

echo "[setup] waiting for MariaDB to report healthy..."
for i in $(seq 1 60); do
    status=$(docker inspect --format='{{.State.Health.Status}}' lab22-primary 2>/dev/null || echo "starting")
    [ "$status" = "healthy" ] && break
    sleep 2
    if [ "$i" -eq 60 ]; then
        echo "[setup] ERROR: lab22-primary never became healthy" >&2
        exit 1
    fi
done

echo "[setup] creating a system-versioned accounts table..."
docker exec lab22-primary mariadb -uroot -prootpass appdb -e "
DROP TABLE IF EXISTS accounts;
CREATE TABLE accounts (
  id INT PRIMARY KEY AUTO_INCREMENT,
  owner VARCHAR(50),
  balance INT
) WITH SYSTEM VERSIONING;
INSERT INTO accounts (owner, balance) VALUES
  ('alice', 1000), ('bob', 500), ('carol', 2500);
"

echo "[setup] simulating months of ordinary balance updates (no special traffic, just normal usage)..."
for i in $(seq 1 400); do
    ACCT=$(( (RANDOM % 3) + 1 ))
    DELTA=$(( (RANDOM % 21) - 10 ))
    docker exec lab22-primary mariadb -uroot -prootpass appdb -e \
        "UPDATE accounts SET balance = balance + ${DELTA} WHERE id = ${ACCT};" 2>/dev/null
done

echo
echo "Done. Try:"
echo '  docker exec lab22-primary mariadb -uroot -prootpass appdb -e "SELECT COUNT(*) FROM accounts;"'
echo '  docker exec lab22-primary mariadb -uroot -prootpass appdb -e "SELECT COUNT(*) FROM accounts FOR SYSTEM_TIME ALL;"'
