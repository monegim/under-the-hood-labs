#!/usr/bin/env bash
# Lab 19 setup — a working ProxySQL + MySQL backend, then the incident:
# the backend user's password gets rotated directly on MySQL without
# updating ProxySQL's copy of it. ProxySQL's own client-facing auth
# still succeeds (its stored password hasn't changed) — the failure
# only happens one layer deeper, when ProxySQL tries to use that same
# (now-stale) password to actually connect to the backend on the
# client's behalf.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary + proxysql..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab19-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[setup] lab19-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: lab19-primary never became healthy" >&2
    exit 1
  fi
done

echo "[setup] waiting for proxysql admin interface to accept connections..."
for i in $(seq 1 30); do
  if docker exec lab19-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT 1;" >/dev/null 2>&1; then
    echo "[setup] proxysql admin interface is up"
    break
  fi
  sleep 2
  if [ "$i" -eq 30 ]; then
    echo "[setup] ERROR: proxysql admin interface never came up" >&2
    exit 1
  fi
done

echo "[setup] creating app user and monitor user on the backend..."
docker exec lab19-primary mysql -uroot -prootpass -e "
  CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED WITH mysql_native_password BY 'apppass';
  GRANT ALL PRIVILEGES ON appdb.* TO 'appuser'@'%';
  CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED WITH mysql_native_password BY 'monitorpass';
  GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%';
"

echo "[setup] configuring ProxySQL: backend, user, monitor..."
docker exec lab19-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  SET mysql-monitor_username='monitor';
  SET mysql-monitor_password='monitorpass';
  LOAD MYSQL VARIABLES TO RUNTIME;

  DELETE FROM mysql_servers;
  INSERT INTO mysql_servers (hostgroup_id, hostname, port) VALUES (10, 'primary', 3306);

  DELETE FROM mysql_users;
  INSERT INTO mysql_users (username, password, default_hostgroup, active) VALUES ('appuser', 'apppass', 10, 1);

  LOAD MYSQL SERVERS TO RUNTIME;
  LOAD MYSQL USERS TO RUNTIME;
  SAVE MYSQL SERVERS TO DISK;
  SAVE MYSQL USERS TO DISK;
"

echo "[setup] confirming the baseline works..."
docker exec lab19-proxysql mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e "SELECT 'baseline ok' AS result;"

echo "[setup] INJECTING THE FAULT: rotating appuser's password directly on the backend..."
docker exec lab19-primary mysql -uroot -prootpass -e "
  ALTER USER 'appuser'@'%' IDENTIFIED WITH mysql_native_password BY 'rotated-backend-pass';
"

# The rotation above does NOT break anything yet: ProxySQL is still holding
# the pooled backend connection it opened during the baseline check, and
# MySQL doesn't invalidate an already-authenticated session just because the
# user's password changed later. In a real incident this is exactly what
# makes it confusing — things keep working for a while after the rotation,
# then fail once a pooled connection finally gets recycled. To make the lab
# reproduce deterministically instead of "maybe in a few minutes", force
# that recycling now by killing appuser's connection on the backend so
# ProxySQL is forced to open a fresh one (with its now-stale password) on
# the next query.
echo "[setup] forcing ProxySQL's pooled backend connection to recycle..."
docker exec lab19-primary mysql -uroot -prootpass -e "
  SET @id = (SELECT id FROM information_schema.processlist WHERE user='appuser' LIMIT 1);
  SET @sql = CONCAT('KILL ', @id);
  PREPARE stmt FROM @sql;
  EXECUTE stmt;
"

echo
echo "Done. ProxySQL still thinks appuser's password is 'apppass' — the backend now expects something else."
echo "Try the same query that just worked:"
echo "  docker exec lab19-proxysql mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e \"SELECT 1;\""
