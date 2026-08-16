#!/usr/bin/env bash
# Lab 14 setup — a primary with two replicas. One replica (replica-a)
# stays fully caught up; the other (replica-b) is deliberately stopped
# before a final write burst, so it's missing the most recent
# transactions when the primary "fails" (stopped, not just crashed —
# this lab is about the promotion decision, not corruption recovery).
set -euo pipefail

cd "$(dirname "$0")"

echo "[setup] bringing up primary, replica-a, replica-b..."
docker compose up -d

echo "[setup] waiting for all three to report healthy..."
for svc in lab14-primary lab14-replica-a lab14-replica-b; do
  for i in $(seq 1 60); do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$svc" 2>/dev/null || echo "starting")
    if [ "$status" = "healthy" ]; then
      echo "[setup] $svc is healthy"
      break
    fi
    sleep 3
    if [ "$i" -eq 60 ]; then
      echo "[setup] ERROR: $svc never became healthy" >&2
      exit 1
    fi
  done
done

# The official mysql image briefly restarts (temp init server -> real
# server) right after first reporting healthy; a command issued in that
# exact window can hit "Can't connect to local MySQL server through
# socket". A short settle buffer avoids racing it.
echo "[setup] letting all three settle past their post-init restart..."
sleep 5

echo "[setup] creating replication user on primary..."
docker exec lab14-primary mysql -uroot -prootpass -e "
  CREATE USER IF NOT EXISTS 'repl'@'%' IDENTIFIED WITH mysql_native_password BY 'replpass';
  GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
  FLUSH PRIVILEGES;
"

echo "[setup] pointing both replicas at the primary (GTID auto-position)..."
for r in lab14-replica-a lab14-replica-b; do
  docker exec "$r" mysql -uroot -prootpass -e "
    CHANGE REPLICATION SOURCE TO
      SOURCE_HOST='primary',
      SOURCE_USER='repl',
      SOURCE_PASSWORD='replpass',
      SOURCE_AUTO_POSITION=1;
    START REPLICA;
  "
done
sleep 3

echo "[setup] creating schema and baseline data on primary..."
docker exec lab14-primary mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS orders;
  CREATE TABLE orders (id INT AUTO_INCREMENT PRIMARY KEY, item VARCHAR(50));
  INSERT INTO orders (item) VALUES ('widget'), ('gadget');
"
sleep 3

echo "[setup] stopping replication on replica-b (simulating it falling behind)..."
docker exec lab14-replica-b mysql -uroot -prootpass -e "STOP REPLICA;"

echo "[setup] writing final orders on primary — only replica-a will see these..."
docker exec lab14-primary mysql -uroot -prootpass appdb -e "
  INSERT INTO orders (item) VALUES ('final-order-1'), ('final-order-2');
"
sleep 3

echo "[setup] simulating primary failure (stopping the container)..."
docker stop lab14-primary >/dev/null

echo
echo "Done. Compare what each replica actually has:"
echo "  docker exec lab14-replica-a mysql -uroot -prootpass appdb -e \"SELECT * FROM orders;\""
echo "  docker exec lab14-replica-b mysql -uroot -prootpass appdb -e \"SELECT * FROM orders;\""
