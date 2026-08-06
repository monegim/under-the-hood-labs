#!/usr/bin/env bash
# Lab 12 setup — a normal MySQL primary/replica pair behind ProxySQL,
# configured for read/write splitting (writes -> primary, reads ->
# replica) — except the hostgroup assignment in mysql_servers is
# deliberately SWAPPED: the primary is registered under the "read"
# hostgroup and the replica under the "write" hostgroup. This is one of
# the most common real ProxySQL misconfigurations: it's a one-line typo
# in an INSERT statement, and ProxySQL will happily run with it forever
# with no startup error, because from ProxySQL's point of view both
# hostgroups have a healthy, reachable MySQL server in them.
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary, replica, proxysql..."
docker compose up -d

echo "[setup] waiting for primary and replica to report healthy..."
for svc in lab12-primary lab12-replica; do
  for i in $(seq 1 60); do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$svc" 2>/dev/null || echo "starting")
    if [ "$status" = "healthy" ]; then
      echo "[setup] $svc is healthy"
      break
    fi
    sleep 3
    if [ "$i" -eq 60 ]; then
      echo "[setup] ERROR: $svc never became healthy, check 'docker logs $svc'"
      exit 1
    fi
  done
done

echo "[setup] creating replication + app users on primary..."
docker exec lab12-primary mysql -uroot -prootpass -e "
  CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'replpass';
  GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
  CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED WITH mysql_native_password BY 'apppass';
  GRANT ALL PRIVILEGES ON appdb.* TO 'appuser'@'%';
  CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED WITH mysql_native_password BY 'monitorpass';
  GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%';
  FLUSH PRIVILEGES;
"

echo "[setup] pointing replica at primary (GTID auto-position)..."
docker exec lab12-replica mysql -uroot -prootpass -e "
  CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED WITH mysql_native_password BY 'apppass';
  GRANT ALL PRIVILEGES ON appdb.* TO 'appuser'@'%';
  CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED WITH mysql_native_password BY 'monitorpass';
  GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%';
  FLUSH PRIVILEGES;
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='primary',
    SOURCE_USER='repl',
    SOURCE_PASSWORD='replpass',
    SOURCE_AUTO_POSITION=1;
  START REPLICA;
"

sleep 3
echo "[setup] replica status:"
docker exec lab12-replica mysql -uroot -prootpass -e "SHOW REPLICA STATUS\G" \
  | grep -E "Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source"

echo "[setup] creating schema on primary..."
docker exec lab12-primary mysql -uroot -prootpass appdb -e "
  CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );
  INSERT INTO orders (data) VALUES ('seed-1'), ('seed-2');
"

echo "[setup] waiting for proxysql admin interface to accept connections..."
for i in $(seq 1 30); do
  if docker exec lab12-primary mysql -h proxysql -P 6032 -u admin -padmin -e "SELECT 1;" >/dev/null 2>&1; then
    echo "[setup] proxysql admin interface is up"
    break
  fi
  sleep 2
  if [ "$i" -eq 30 ]; then
    echo "[setup] ERROR: proxysql admin interface never came up, check 'docker logs lab12-proxysql'"
    exit 1
  fi
done

echo "[setup] configuring ProxySQL — INJECTING THE FAULT: hostgroups are SWAPPED"
echo "[setup] (primary -> hostgroup 20 'read', replica -> hostgroup 10 'write')"
docker exec lab12-primary mysql -h proxysql -P 6032 -u admin -padmin -e "
  SET mysql-monitor_username='monitor';
  SET mysql-monitor_password='monitorpass';
  LOAD MYSQL VARIABLES TO RUNTIME;
  SAVE MYSQL VARIABLES TO DISK;

  DELETE FROM mysql_servers;
  INSERT INTO mysql_servers (hostgroup_id, hostname, port) VALUES
    (20, 'primary', 3306),
    (10, 'replica', 3306);

  DELETE FROM mysql_users;
  INSERT INTO mysql_users (username, password, default_hostgroup, active) VALUES
    ('appuser', 'apppass', 10, 1);

  DELETE FROM mysql_query_rules;
  INSERT INTO mysql_query_rules (rule_id, active, match_pattern, destination_hostgroup, apply) VALUES
    (1, 1, '^SELECT.*FOR UPDATE', 10, 1),
    (2, 1, '^SELECT', 20, 1);

  LOAD MYSQL SERVERS TO RUNTIME;
  LOAD MYSQL USERS TO RUNTIME;
  LOAD MYSQL QUERY RULES TO RUNTIME;
  SAVE MYSQL SERVERS TO DISK;
  SAVE MYSQL USERS TO DISK;
  SAVE MYSQL QUERY RULES TO DISK;
"

echo "[setup] current mysql_servers hostgroup assignment (this is the bug — read it carefully):"
docker exec lab12-primary mysql -h proxysql -P 6032 -u admin -padmin -e "
  SELECT hostgroup_id, hostname, port, status FROM mysql_servers;
"

echo "[setup] done. Try a write through ProxySQL to see it fail:"
echo "  docker exec lab12-primary mysql -h proxysql -P 6033 -u appuser -papppass appdb -e \"INSERT INTO orders (data) VALUES ('via-proxysql');\""
