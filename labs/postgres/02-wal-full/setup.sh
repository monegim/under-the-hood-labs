#!/usr/bin/env bash
# Lab 32 setup — pg_wal fills a bounded disk because a physical
# replication slot is created and then never consumed by anything,
# pinning WAL at its creation-time restart_lsn and preventing recycling.
#
# Needs sudo: builds a small (300MB) loop-mounted ext4 filesystem on the
# HOST and bind-mounts it into the primary as its WAL directory
# (--waldir), so "the disk fills" is safely bounded instead of actually
# filling your real disk. Same pattern as labs/linux/11's inode lab, just
# combined with docker-compose this time.
set -euo pipefail

cd "$(dirname "$0")"

WAL_DISK_IMG="$(pwd)/data/wal-disk.img"
WAL_DISK_MNT="$(pwd)/data/wal-disk"
WAL_DISK_SIZE_MB=300

echo "[setup] creating a ${WAL_DISK_SIZE_MB}MB backing file for the WAL disk..."
mkdir -p ./data
sudo dd if=/dev/zero of="$WAL_DISK_IMG" bs=1M count="$WAL_DISK_SIZE_MB" status=none

echo "[setup] attaching it as a loop device..."
LOOPDEV=$(sudo losetup --find --show "$WAL_DISK_IMG")
echo "$LOOPDEV" | sudo tee ./data/wal-disk.loopdev > /dev/null
echo "[setup] loop device: $LOOPDEV"

echo "[setup] formatting ext4..."
sudo mkfs.ext4 -q "$LOOPDEV"

echo "[setup] mounting at $WAL_DISK_MNT..."
mkdir -p "$WAL_DISK_MNT"
sudo mount "$LOOPDEV" "$WAL_DISK_MNT"
sudo chmod 777 "$WAL_DISK_MNT"

echo "[setup] bringing up primary (WAL directory pointed at the bounded disk)..."
docker compose up -d

echo "[setup] waiting for primary to report healthy..."
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' lab32-primary 2>/dev/null || echo "starting")
  if [ "$status" = "healthy" ]; then
    echo "[setup] lab32-primary is healthy"
    break
  fi
  sleep 3
  if [ "$i" -eq 60 ]; then
    echo "[setup] ERROR: lab32-primary never became healthy, check 'docker logs lab32-primary'"
    exit 1
  fi
done

echo "[setup] creating schema..."
docker exec lab32-primary psql -U postgres -d appdb -c "
  CREATE TABLE IF NOT EXISTS bloatme (id SERIAL PRIMARY KEY, data TEXT);
"

echo "[setup] creating a physical replication slot that nothing will ever consume from..."
docker exec lab32-primary psql -U postgres -c \
  "SELECT pg_create_physical_replication_slot('stuck_slot');"

echo "[setup] confirming the slot exists and is inactive:"
docker exec lab32-primary psql -U postgres -c \
  "SELECT slot_name, active, restart_lsn FROM pg_replication_slots;"

echo "[setup] generating write volume to fill the bounded WAL disk (bounded: max 60 iterations)..."
echo "[setup] this is EXPECTED to eventually fail writes once the WAL disk is full — that IS the incident."
set +e
docker exec lab32-primary bash -c '
  for i in $(seq 1 60); do
    psql -U postgres -d appdb -c "INSERT INTO bloatme (data) SELECT repeat(chr(65+(random()*25)::int),1000) FROM generate_series(1,20000);" 2>&1 | tail -1
    psql -U postgres -d appdb -c "DELETE FROM bloatme;" >/dev/null 2>&1
    df -h /pgwal 2>/dev/null | tail -1
  done
'
set -e

echo "[setup] done. Check WAL disk usage and the slot:"
echo "    df -h $WAL_DISK_MNT"
echo "    docker exec lab32-primary psql -U postgres -c \"SELECT slot_name, active, restart_lsn, wal_status FROM pg_replication_slots;\""
