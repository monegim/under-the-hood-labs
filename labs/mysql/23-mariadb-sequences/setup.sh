#!/usr/bin/env bash
# Lab 23 setup - builds a MariaDB instance with a SEQUENCE object (no
# MySQL equivalent) backing an invoices table's IDs, with a CACHE of
# 100 - a completely reasonable-looking performance setting. Issues a
# handful of real invoice numbers, then restarts the container (a
# routine restart - a deploy, a host reboot, nothing unusual) to show
# the incident already in progress by the time you arrive.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p ./data/mysql

echo "[setup] starting MariaDB..."
docker compose up -d

echo "[setup] waiting for MariaDB to report healthy..."
for i in $(seq 1 60); do
    status=$(docker inspect --format='{{.State.Health.Status}}' lab23-primary 2>/dev/null || echo "starting")
    [ "$status" = "healthy" ] && break
    sleep 2
    if [ "$i" -eq 60 ]; then
        echo "[setup] ERROR: lab23-primary never became healthy" >&2
        exit 1
    fi
done

echo "[setup] creating invoice_seq (CACHE 100) and issuing a few real invoice numbers..."
docker exec lab23-primary mariadb -uroot -prootpass appdb -e "
DROP TABLE IF EXISTS invoices;
DROP SEQUENCE IF EXISTS invoice_seq;
CREATE SEQUENCE invoice_seq START WITH 1 INCREMENT BY 1 CACHE 100;
CREATE TABLE invoices (
  id BIGINT PRIMARY KEY DEFAULT (NEXTVAL(invoice_seq)),
  customer VARCHAR(50)
);
INSERT INTO invoices (customer) VALUES ('acme-co');
INSERT INTO invoices (customer) VALUES ('widget-inc');
INSERT INTO invoices (customer) VALUES ('foo-llc');
"

echo "[setup] INJECTING THE FAULT: restarting MariaDB (a routine restart, nothing unusual)..."
docker compose restart primary
for i in $(seq 1 60); do
    status=$(docker inspect --format='{{.State.Health.Status}}' lab23-primary 2>/dev/null || echo "starting")
    [ "$status" = "healthy" ] && break
    sleep 2
done

echo "[setup] issuing one more invoice number after the restart..."
docker exec lab23-primary mariadb -uroot -prootpass appdb -e "
INSERT INTO invoices (customer) VALUES ('bar-corp');
"

echo
echo "Done. Try:"
echo '  docker exec lab23-primary mariadb -uroot -prootpass appdb -e "SELECT * FROM invoices ORDER BY id;"'
