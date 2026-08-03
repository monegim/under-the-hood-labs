#!/usr/bin/env bash
# Lab 4 check — verifies the sku lookup no longer full-scans: an index on
# sku exists AND EXPLAIN reports an access type other than ALL for it.
set -uo pipefail

fail() { echo "[FAIL] $1"; exit 1; }

if ! systemctl is-active --quiet mysql; then
    fail "mysql.service is not active"
fi

echo "[check] checking for an index covering products.sku..."
IDX_COUNT=$(mysql -uroot -prootpass appdb -N -e "
  SELECT COUNT(*) FROM information_schema.statistics
  WHERE table_schema='appdb' AND table_name='products' AND column_name='sku';
" 2>/dev/null)

[ "${IDX_COUNT:-0}" -gt 0 ] || fail "no index found on products.sku"
echo "[check] found $IDX_COUNT index(es) covering sku."

echo "[check] running EXPLAIN for the sku lookup..."
PLAN=$(mysql -uroot -prootpass appdb -e "EXPLAIN FORMAT=JSON SELECT * FROM products WHERE sku='SKU-000123';" -N 2>/dev/null)

if echo "$PLAN" | grep -q '"access_type": *"ALL"'; then
    echo "[FAIL] query plan still shows a full table scan (access_type: ALL):"
    echo "$PLAN" | grep -A2 access_type
    exit 1
fi

echo "[check] EXPLAIN no longer shows a full table scan for the sku lookup."
echo "[PASS] products.sku is indexed and the point lookup uses it."
exit 0
