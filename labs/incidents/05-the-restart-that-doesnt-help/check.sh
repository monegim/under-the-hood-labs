#!/usr/bin/env bash
# Incident 05 check - mirrors how this was paged: is the upload queue
# actually draining? Drops a small test file into the pending directory
# and confirms upload-worker actually processes it, and that nothing is
# still stuck in D state.
set -uo pipefail

PENDING="/var/lib/uploadlab/pending"
UPLOADED="/mnt/uploads"
TESTFILE="check-$$.txt"

if ! mountpoint -q /mnt/uploads 2>/dev/null; then
    echo "[FAIL] /mnt/uploads is not mounted."
    exit 1
fi

echo "[check] dropping a small test file into the pending queue..."
echo "healthcheck $$" | sudo tee "$PENDING/$TESTFILE" >/dev/null

echo "[check] waiting up to 15s for upload-worker to process it..."
FOUND=0
for i in $(seq 1 15); do
    if [ -f "$UPLOADED/$TESTFILE" ]; then
        FOUND=1
        break
    fi
    sleep 1
done

if [ "$FOUND" -eq 0 ]; then
    echo "[FAIL] test file was never processed - the upload queue is still stuck."
    echo "[check] current upload-worker processes:"
    ps -eo pid,ppid,stat,wchan:32,cmd | grep '[u]pload-worker.py' || echo "  (none found)"
    exit 1
fi

echo "[check] checking for any upload-worker process still stuck in D state..."
STUCK=$(ps -eo pid,stat,cmd | awk '$2 ~ /^D/ && /upload-worker.py/')
if [ -n "$STUCK" ]; then
    echo "[FAIL] found a D-state upload-worker process still present:"
    echo "$STUCK"
    exit 1
fi

sudo rm -f "$UPLOADED/$TESTFILE"
echo "[PASS] the upload queue is draining normally and nothing is stuck in D state."
exit 0
