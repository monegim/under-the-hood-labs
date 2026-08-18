#!/usr/bin/env bash
# Lab 21 check - fires a fresh batch of realistic random point lookups
# across working_set's full ID range and requires the buffer pool hit
# ratio for that batch to be at or above what a properly-sized pool
# actually achieves (~97%, verified) - well above what an undersized
# pool can ever sustain for a working set that doesn't fit (~86-89%,
# verified, and stable - it does not improve with more warming).
set -uo pipefail

THRESHOLD=93

if ! docker exec lab21-primary mysqladmin ping -h localhost -uroot -prootpass >/dev/null 2>&1; then
    echo "[FAIL] lab21-primary is not reachable - run setup.sh first"
    exit 1
fi

BEFORE_R=$(docker exec lab21-primary mysql -uroot -prootpass -N -e "SHOW STATUS LIKE 'Innodb_buffer_pool_reads';" | awk '{print $2}')
BEFORE_RQ=$(docker exec lab21-primary mysql -uroot -prootpass -N -e "SHOW STATUS LIKE 'Innodb_buffer_pool_read_requests';" | awk '{print $2}')

echo "[check] firing 2000 random point lookups across working_set..."
docker exec lab21-primary bash -c "
for j in \$(seq 1 2000); do
  echo \"SELECT val FROM working_set WHERE id = \$(( (RANDOM * RANDOM * RANDOM) % 320000 + 1 ));\"
done | mysql -uroot -prootpass appdb -N
" >/dev/null

AFTER_R=$(docker exec lab21-primary mysql -uroot -prootpass -N -e "SHOW STATUS LIKE 'Innodb_buffer_pool_reads';" | awk '{print $2}')
AFTER_RQ=$(docker exec lab21-primary mysql -uroot -prootpass -N -e "SHOW STATUS LIKE 'Innodb_buffer_pool_read_requests';" | awk '{print $2}')

DELTA_R=$((AFTER_R - BEFORE_R))
DELTA_RQ=$((AFTER_RQ - BEFORE_RQ))

if [ "$DELTA_RQ" -eq 0 ]; then
    echo "[FAIL] no read requests observed - something is wrong with the test"
    exit 1
fi

HIT_RATIO=$(( (DELTA_RQ - DELTA_R) * 100 / DELTA_RQ ))

echo "[check] this batch: ${DELTA_RQ} logical reads, ${DELTA_R} physical reads, hit ratio ${HIT_RATIO}%"

if [ "$HIT_RATIO" -ge "$THRESHOLD" ]; then
    echo "[PASS] buffer pool hit ratio is ${HIT_RATIO}%, at or above the ${THRESHOLD}% a properly-sized pool sustains."
    exit 0
else
    echo "[FAIL] buffer pool hit ratio is ${HIT_RATIO}%, well below the ${THRESHOLD}% threshold - the working set still doesn't fit."
    exit 1
fi
