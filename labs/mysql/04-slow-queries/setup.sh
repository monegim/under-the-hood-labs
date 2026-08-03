#!/usr/bin/env bash
# Lab 4 setup — a query that "used to be fast" (small table, full scans
# were cheap) becomes slow once the table has real data volume, because
# nobody ever added an index for the lookup pattern the app actually uses.
set -euo pipefail

echo "[1/6] Installing mysql-server..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server > /dev/null

echo "[2/6] Setting a root password so the rest of this lab can script non-interactively..."
sudo mysql -e "
  ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'rootpass';
  FLUSH PRIVILEGES;
" 2>/dev/null || true

echo "[3/6] Enabling the slow query log (long_query_time=0.2s, plus logging any"
echo "      query that doesn't use an index regardless of how fast it runs)..."
sudo tee /etc/mysql/mysql.conf.d/zzz-lab04.cnf > /dev/null <<'EOF'
[mysqld]
slow_query_log=1
slow_query_log_file=/var/log/mysql/mysql-slow.log
long_query_time=0.2
log_queries_not_using_indexes=1
EOF
sudo touch /var/log/mysql/mysql-slow.log
sudo chown mysql:mysql /var/log/mysql/mysql-slow.log
sudo systemctl restart mysql
sleep 2

echo "[4/6] Creating a 1000-row helper sequence table (used to bulk-generate data fast)..."
mysql -uroot -prootpass -e "
  CREATE DATABASE IF NOT EXISTS appdb;
  USE appdb;
  DROP TABLE IF EXISTS seq_helper;
  CREATE TABLE seq_helper (n INT PRIMARY KEY);
  INSERT INTO seq_helper
  WITH RECURSIVE seq AS (
    SELECT 0 AS n
    UNION ALL
    SELECT n+1 FROM seq WHERE n < 999
  )
  SELECT n FROM seq;
"

echo "[5/6] Generating 500,000 rows in 'products' (no index on sku or category —"
echo "      this is the mistake: id is the only indexed column)..."
mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS products;
  CREATE TABLE products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    sku VARCHAR(20) NOT NULL,
    category VARCHAR(50) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    created_at DATETIME NOT NULL
  );
  INSERT INTO products (sku, category, price, created_at)
  SELECT
    CONCAT('SKU-', LPAD(a.n*1000 + b.n, 6, '0')),
    CONCAT('category-', (a.n*1000 + b.n) % 50),
    10 + ((a.n*1000 + b.n) % 5000) / 10,
    DATE_ADD('2023-01-01', INTERVAL (a.n*1000 + b.n) % 700 DAY)
  FROM seq_helper a JOIN seq_helper b
  LIMIT 500000;
  ANALYZE TABLE products;
"
ROWS=$(mysql -uroot -prootpass appdb -N -e "SELECT COUNT(*) FROM products;")
echo "[5/6] products now has $ROWS rows, zero indexes beyond the PRIMARY KEY on id."

echo "[6/6] Simulating app traffic: 20 point lookups by sku (the query the app actually runs)..."
for i in $(seq 1 20); do
  SKU=$(printf "SKU-%06d" $(( (RANDOM * RANDOM) % 500000 )))
  mysql -uroot -prootpass appdb -e "SELECT * FROM products WHERE sku='$SKU';" > /dev/null
done

echo
echo "Done. Start diagnosing:"
echo "  sudo tail -n 40 /var/log/mysql/mysql-slow.log"
echo "  mysql -uroot -prootpass appdb -e \"EXPLAIN SELECT * FROM products WHERE sku='SKU-000123';\""
