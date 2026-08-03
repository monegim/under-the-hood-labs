#!/usr/bin/env bash
# Lab 34 (Index Bloat) check — verifies the index is valid and its leaf
# density (via pgstattuple's pgstatindex) is back in a healthy range.
set -uo pipefail

PRIMARY="lab34-primary"
MIN_LEAF_DENSITY=50   # percent; a freshly rebuilt btree is usually ~90%

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying primary container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$PRIMARY" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PRIMARY is not running (run setup.sh first)"

echo "[check] verifying idx_widgets_sku exists and is valid (not left over from an interrupted REINDEX CONCURRENTLY)..."
VALID=$(docker exec "$PRIMARY" psql -U postgres -d appdb -tAc \
  "SELECT indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = 'idx_widgets_sku';" 2>/dev/null | tr -d ' ')
[ -n "$VALID" ] || fail "could not find index idx_widgets_sku at all"
[ "$VALID" = "t" ] || fail "idx_widgets_sku exists but is NOT valid (indisvalid=false) — a REINDEX CONCURRENTLY was likely interrupted; drop and rebuild it"

echo "[check] checking for leftover invalid indexes from an interrupted REINDEX CONCURRENTLY..."
LEFTOVER=$(docker exec "$PRIMARY" psql -U postgres -d appdb -tAc \
  "SELECT count(*) FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname LIKE 'idx_widgets_sku_cc%' AND i.indisvalid = false;" 2>/dev/null | tr -d ' ')
if [ -n "$LEFTOVER" ] && [ "$LEFTOVER" -gt 0 ]; then
  fail "$LEFTOVER leftover invalid index(es) from an interrupted REINDEX CONCURRENTLY still exist — drop them"
fi

echo "[check] checking avg_leaf_density via pgstatindex..."
DENSITY=$(docker exec "$PRIMARY" psql -U postgres -d appdb -tAc \
  "SELECT round(avg_leaf_density) FROM pgstatindex('idx_widgets_sku');" 2>/dev/null | tr -d ' ')
[ -n "$DENSITY" ] || fail "could not read avg_leaf_density from pgstatindex"

echo "[check] avg_leaf_density=${DENSITY}%"
if [ "$DENSITY" -lt "$MIN_LEAF_DENSITY" ]; then
  fail "avg_leaf_density is ${DENSITY}% (< ${MIN_LEAF_DENSITY}%) — index is still bloated"
fi

echo "[PASS] idx_widgets_sku is valid and avg_leaf_density=${DENSITY}% (>= ${MIN_LEAF_DENSITY}%)"
exit 0
