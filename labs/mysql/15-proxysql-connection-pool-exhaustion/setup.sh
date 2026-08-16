#!/usr/bin/env bash
# Lab 15 setup — ProxySQL sits in front of a single MySQL backend with
# its per-backend connection pool (mysql_servers.max_connections)
# deliberately tiny. 8 clients holding transactions through ProxySQL
# exhaust that pool, while the backend itself stays nearly idle.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary + proxysql..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab15-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[setup] lab15-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: lab15-primary never became healthy" >&2
    exit 1
  fi
done

echo "[setup] waiting for proxysql admin interface to accept connections..."
for i in $(seq 1 30); do
  if docker exec lab15-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT 1;" >/dev/null 2>&1; then
    echo "[setup] proxysql admin interface is up"
    break
  fi
  sleep 2
  if [ "$i" -eq 30 ]; then
    echo "[setup] ERROR: proxysql admin interface never came up, check 'docker logs lab15-proxysql'" >&2
    exit 1
  fi
done

echo "[setup] creating app user on the backend..."
docker exec lab15-primary mysql -uroot -prootpass -e "
  CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED WITH mysql_native_password BY 'apppass';
  GRANT ALL PRIVILEGES ON appdb.* TO 'appuser'@'%';
  FLUSH PRIVILEGES;
"

echo "[setup] creating schema..."
docker exec lab15-primary mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS widgets;
  CREATE TABLE widgets (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(50));
"

echo "[setup] configuring ProxySQL — INJECTING THE FAULT: per-backend max_connections=5..."
docker exec lab15-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  DELETE FROM mysql_servers;
  INSERT INTO mysql_servers (hostgroup_id, hostname, port, max_connections) VALUES (10, 'primary', 3306, 5);

  DELETE FROM mysql_users;
  INSERT INTO mysql_users (username, password, default_hostgroup, active, max_connections) VALUES
    ('appuser', 'apppass', 10, 1, 10000);

  LOAD MYSQL SERVERS TO RUNTIME;
  LOAD MYSQL USERS TO RUNTIME;
  SAVE MYSQL SERVERS TO DISK;
  SAVE MYSQL USERS TO DISK;
"

echo "[setup] launching 8 clients through ProxySQL, each holding a 30s transaction..."
echo "[setup] (pool max_connections=5 on the backend — the 6th, 7th, 8th will queue)"
for i in $(seq 1 8); do
  docker exec -d lab15-proxysql sh -c "
    mysql -h127.0.0.1 -P6033 -uappuser -papppass appdb -e \"
      BEGIN;
      INSERT INTO widgets (name) VALUES ('client-$i');
      SELECT SLEEP(30);
      COMMIT;
    \" > /tmp/client-$i.log 2>&1
  "
done

sleep 3
echo "[setup] done. Check the pool:"
echo "  docker exec lab15-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e 'SELECT hostgroup, srv_host, status, ConnUsed, ConnFree FROM stats_mysql_connection_pool;'"
