#!/usr/bin/env bash
# Lab 11 (Partition Pruning Failure) check — this lab's "incident" is a
# query-authoring pattern, not persistent broken server state, so check.sh
# verifies the environment itself still supports pruning correctly: a
# canonical sargable date-range query must prune to exactly one partition.
# (If this ever fails, the table/partitioning itself is broken, not just a
# query you wrote badly.)
set -uo pipefail

PRIMARY="lab11-primary"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying primary container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$PRIMARY" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PRIMARY is not running (run setup.sh first)"

echo "[check] verifying events table exists and is partitioned..."
PART_COUNT=$(docker exec "$PRIMARY" mysql -uroot -prootpass appdb -N -e "
  SELECT COUNT(*) FROM information_schema.PARTITIONS
  WHERE TABLE_SCHEMA='appdb' AND TABLE_NAME='events' AND PARTITION_NAME IS NOT NULL;
" 2>/dev/null)
[ "$PART_COUNT" = "5" ] || fail "expected 5 partitions on events, found '$PART_COUNT'"

echo "[check] verifying a sargable date-range query prunes to exactly p2024..."
PARTITIONS=$(docker exec "$PRIMARY" mysql -uroot -prootpass appdb -N -e "
  EXPLAIN SELECT COUNT(*) FROM events
  WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';
" 2>/dev/null | awk -F'\t' '{print $4}')

echo "[check] partitions scanned: $PARTITIONS"
if [ "$PARTITIONS" != "p2024" ]; then
  fail "expected pruning to p2024 only, got '$PARTITIONS' — partitioning/pruning is not working as expected"
fi

echo "[PASS] partition pruning is working correctly (sargable query prunes to p2024 only)"
exit 0
