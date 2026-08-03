#!/usr/bin/env bash
# Lab 3 setup — two transactions deadlock via classic opposite-order lock
# acquisition (transaction A locks row 1 then row 2, transaction B locks
# row 2 then row 1). InnoDB's deadlock detector picks a victim, rolls it
# back with error 1213, and lets the other one commit — leaving exactly
# ONE of the two "transfers" applied instead of both.
set -euo pipefail

echo "[1/5] Installing mysql-server..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server > /dev/null

echo "[2/5] Setting a root password so the rest of this lab can script non-interactively..."
sudo mysql -e "
  ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'rootpass';
  FLUSH PRIVILEGES;
" 2>/dev/null || true
sudo systemctl restart mysql
sleep 2

echo "[3/5] Creating schema (accounts, id is a plain business key so the deadlock is deterministic)..."
mysql -uroot -prootpass -e "
  CREATE DATABASE IF NOT EXISTS appdb;
  USE appdb;
  DROP TABLE IF EXISTS accounts;
  CREATE TABLE accounts (
    id INT PRIMARY KEY,
    balance INT NOT NULL
  );
  INSERT INTO accounts (id, balance) VALUES (1, 1000), (2, 1000);
"

echo "[4/5] Firing two transfers concurrently, in OPPOSITE row lock order:"
echo "      transfer A: locks id=1, sleeps, then locks id=2 (moves 100 from 1 -> 2)"
echo "      transfer B: locks id=2, sleeps, then locks id=1 (moves  50 from 2 -> 1)"
mysql -uroot -prootpass appdb -e "
  BEGIN;
  UPDATE accounts SET balance = balance - 100 WHERE id = 1;
  DO SLEEP(2);
  UPDATE accounts SET balance = balance + 100 WHERE id = 2;
  COMMIT;
" > /tmp/lab03-transfer-a.log 2>&1 &
PID_A=$!

mysql -uroot -prootpass appdb -e "
  BEGIN;
  UPDATE accounts SET balance = balance - 50 WHERE id = 2;
  DO SLEEP(2);
  UPDATE accounts SET balance = balance + 50 WHERE id = 1;
  COMMIT;
" > /tmp/lab03-transfer-b.log 2>&1 &
PID_B=$!

wait "$PID_A" || true
wait "$PID_B" || true

echo "[5/5] done. Transfer A log:"
cat /tmp/lab03-transfer-a.log || true
echo "Transfer B log:"
cat /tmp/lab03-transfer-b.log || true

echo
echo "One of the two above should show:"
echo "  ERROR 1213 (40001) at line N: Deadlock found when trying to get lock; try restarting transaction"
echo
echo "Current (inconsistent) balances:"
mysql -uroot -prootpass appdb -e "SELECT * FROM accounts;"
echo
echo "Start diagnosing:"
echo "  mysql -uroot -prootpass -e \"SHOW ENGINE INNODB STATUS\\G\" | less"
