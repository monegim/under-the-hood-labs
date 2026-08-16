#!/usr/bin/env bash
# Lab 9 check — general health check: is quota accounting on, and can
# user 'nobody' currently write to the lab filesystem without hitting
# their quota.
set -uo pipefail

PASS=0
MNT=/mnt/quotadata

if ! mountpoint -q "$MNT" 2>/dev/null; then
    echo "[FAIL] $MNT is not mounted."
    exit 1
fi

echo "[check] quota -u nobody:"
sudo quota -u nobody 2>&1 || true

TESTFILE="$MNT/.check_write_test_$$"
if echo "healthcheck" | sudo -u nobody tee "$TESTFILE" >/dev/null 2>&1; then
    echo "[check] write to $MNT as nobody succeeded."
    sudo rm -f "$TESTFILE"
else
    echo "[FAIL] write to $MNT as nobody failed (quota or space exhausted)."
    PASS=1
fi

echo "[check] extra file-count check (Challenge B may still have nobody near an inode cap)..."
TESTFILE2="$MNT/.check_inode_test_$$"
if sudo -u nobody touch "$TESTFILE2" 2>&1; then
    sudo rm -f "$TESTFILE2"
else
    echo "[FAIL] creating a new file as nobody failed."
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] nobody can write data and create files on $MNT without hitting quota."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
