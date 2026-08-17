#!/usr/bin/env bash
# Lab 20 setup — configure ProxySQL routing under pressure, the way it
# actually happens: LOAD it to RUNTIME to fix things right now, and never
# circle back to SAVE it TO DISK. Everything keeps working — until
# something restarts the ProxySQL process for a completely unrelated
# reason, and the fix quietly reverts to nothing.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary + proxysql..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  hstatus=$(docker inspect -f '{{.State.Health.Status}}' lab20-primary 2>/dev/null || echo "starting")
  if [ "$hstatus" = "healthy" ]; then
    echo "[setup] lab20-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: lab20-primary never became healthy" >&2
    exit 1
  fi
done

echo "[setup] waiting for proxysql admin interface to accept connections..."
for i in $(seq 1 30); do
  if docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT 1;" >/dev/null 2>&1; then
    echo "[setup] proxysql admin interface is up"
    break
  fi
  sleep 2
  if [ "$i" -eq 30 ]; then
    echo "[setup] ERROR: proxysql admin interface never came up" >&2
    exit 1
  fi
done

echo "[setup] creating app user on the backend..."
docker exec lab20-primary mysql -uroot -prootpass -e "
  CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED WITH mysql_native_password BY 'apppass';
  GRANT ALL PRIVILEGES ON appdb.* TO 'appuser'@'%';
"

echo "[setup] configuring ProxySQL: backend + user, loaded to RUNTIME only (this is the incident-in-waiting — no SAVE TO DISK)..."
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  DELETE FROM mysql_servers;
  INSERT INTO mysql_servers (hostgroup_id, hostname, port) VALUES (10, 'primary', 3306);

  DELETE FROM mysql_users;
  INSERT INTO mysql_users (username, password, default_hostgroup, active) VALUES ('appuser', 'apppass', 10, 1);

  LOAD MYSQL SERVERS TO RUNTIME;
  LOAD MYSQL USERS TO RUNTIME;
"

echo "[setup] confirming it works right now..."
docker exec lab20-proxysql mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e "SELECT 'baseline ok' AS result;"

# The routing above only exists in ProxySQL's RUNTIME memory - it was never
# SAVEd TO DISK. That alone isn't broken yet; nothing forces ProxySQL to
# reload from disk while it just keeps running. The incident needs a
# restart to actually happen - so simulate the routine, unrelated kind (an
# upgrade, a host reboot, an orchestrator rescheduling the pod) that
# triggers it in the real world.
echo "[setup] INJECTING THE FAULT: restarting ProxySQL (simulating a routine restart)..."
docker compose restart proxysql
sleep 5

echo
echo "Done. ProxySQL restarted and reloaded from disk - which never had this config on it."
echo "Try the query that just worked:"
echo "  docker exec lab20-proxysql mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e \"SELECT 1;\""
