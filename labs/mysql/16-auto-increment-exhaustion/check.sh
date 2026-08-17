#!/usr/bin/env bash
# Lab 16 check — verifies a fresh insert succeeds AND that the column
# type actually has real headroom left above the current counter value
# (not just that one more insert happened to squeak through).
set -uo pipefail

PRIMARY="lab16-primary"

fail() { echo "[FAIL] $1"; exit 1; }

echo "[check] verifying primary container is running..."
status=$(docker inspect -f '{{.State.Running}}' "$PRIMARY" 2>/dev/null)
[ "$status" = "true" ] || fail "container $PRIMARY is not running (run setup.sh first)"

echo "[check] attempting a fresh insert..."
if ! docker exec "$PRIMARY" mysql -uroot -prootpass appdb -e "INSERT INTO orders (data) VALUES ('check-probe');" 2>/tmp/lab16-check-err; then
    fail "insert failed: $(cat /tmp/lab16-check-err)"
fi

echo "[check] reading current column type and counter value..."
COLTYPE=$(docker exec "$PRIMARY" mysql -uroot -prootpass -N -e "
  SELECT COLUMN_TYPE FROM information_schema.columns
  WHERE table_schema='appdb' AND table_name='orders' AND column_name='id';
" 2>/dev/null)
COUNTER=$(docker exec "$PRIMARY" mysql -uroot -prootpass appdb -N -e "SHOW CREATE TABLE orders;" 2>/dev/null \
  | grep -oE "AUTO_INCREMENT=[0-9]+" | grep -oE "[0-9]+")

echo "[check] column type: $COLTYPE, current counter: $COUNTER"

MAXVAL=0
case "$COLTYPE" in
  "tinyint unsigned") MAXVAL=255 ;;
  "tinyint") MAXVAL=127 ;;
  "smallint unsigned") MAXVAL=65535 ;;
  "smallint") MAXVAL=32767 ;;
  "mediumint unsigned") MAXVAL=16777215 ;;
  "mediumint") MAXVAL=8388607 ;;
  "int unsigned") MAXVAL=4294967295 ;;
  "int") MAXVAL=2147483647 ;;
  *) MAXVAL=-1 ;;  # bigint or unrecognized — treat as effectively unbounded for this lab
esac

if [ "$MAXVAL" -ge 0 ]; then
  HEADROOM=$((MAXVAL - COUNTER))
  echo "[check] column max is $MAXVAL, headroom remaining: $HEADROOM"
  if [ "$HEADROOM" -lt 1000 ]; then
    fail "less than 1000 values of headroom remain ($HEADROOM) — widen the column further"
  fi
fi

echo "[PASS] inserts succeed and the column has real headroom above the current counter."
exit 0
