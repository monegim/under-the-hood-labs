#!/usr/bin/env bash
# Lab 12 setup — builds a Docker storage bloat incident on an isolated
# loop-device-backed filesystem: a second, dedicated dockerd instance
# with its data-root pointed at /mnt/dockerlab (never the host's real
# /var/lib/docker), populated with dangling images from repeated
# rebuilds, stopped-but-not-removed containers, and a couple of named
# volumes.
#
# Using a loop device + a separate dockerd instance/socket keeps this
# safe and reversible: nothing here touches the host's real Docker
# images, containers, volumes, or /var/lib/docker. Teardown is stopping
# the lab dockerd + unmount + losetup -d.
set -euo pipefail

STATE_DIR=/var/lib/dockerlab
MNT=/mnt/dockerlab
SOCK=/var/run/dockerlab.sock
PIDFILE=/var/run/dockerlab.pid
LOG=/var/log/dockerlab.log
DOCKER="sudo docker -H unix://$SOCK"

echo "[1/8] checking docker is installed..."
if ! command -v dockerd >/dev/null 2>&1; then
  echo "dockerd not found - install Docker Engine first (see README Prerequisites)." >&2
  exit 1
fi

echo "[2/8] creating a 1G backing file..."
sudo mkdir -p "$STATE_DIR"
sudo dd if=/dev/zero of="$STATE_DIR/disk.img" bs=1M count=1024 status=none

echo "[3/8] attaching it as a loop device and formatting with ext4..."
LOOPDEV=$(sudo losetup --find --show "$STATE_DIR/disk.img")
echo "$LOOPDEV" | sudo tee "$STATE_DIR/loopdev" > /dev/null
sudo mkfs.ext4 -q "$LOOPDEV"
sudo mkdir -p "$MNT"
sudo mount "$LOOPDEV" "$MNT"
echo "      loop device: $LOOPDEV, mounted at $MNT"

echo "[4/8] starting a dedicated dockerd instance on $SOCK with data-root=$MNT..."
sudo dockerd \
    --data-root "$MNT" \
    --host "unix://$SOCK" \
    --pidfile "$PIDFILE" \
    --bridge=none \
    > "$LOG" 2>&1 &
disown

echo "      waiting for the lab dockerd to come up..."
for i in $(seq 1 30); do
    if $DOCKER info >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
if ! $DOCKER info >/dev/null 2>&1; then
    echo "lab dockerd did not come up in time - check $LOG" >&2
    exit 1
fi

echo "[5/8] pulling the alpine base image..."
$DOCKER pull -q alpine:latest

echo "[6/8] building myapp:latest three times over, leaving old versions"
echo "      dangling each time a rebuild changes the tag's target..."
BUILD_DIR="$STATE_DIR/build"
sudo mkdir -p "$BUILD_DIR"
for v in 1 2 3; do
    sudo tee "$BUILD_DIR/Dockerfile" > /dev/null <<EOF
FROM alpine:latest
RUN echo "version $v" > /version && dd if=/dev/urandom of=/pad bs=1M count=5
EOF
    $DOCKER build -q -t myapp:latest "$BUILD_DIR" > /dev/null
done

echo "[7/8] running a few containers from myapp:latest and stopping (not removing) them..."
for i in 1 2 3; do
    $DOCKER run -d --network none --name "stopped_app_$i" myapp:latest sleep 300 > /dev/null
done
sleep 1
for i in 1 2 3; do
    $DOCKER stop "stopped_app_$i" > /dev/null
done

echo "[8/8] creating named volumes (one of them unattached, simulating leftovers)..."
$DOCKER volume create dockerlab_appdata > /dev/null
$DOCKER volume create dockerlab_orphaned_logs > /dev/null
$DOCKER run --rm --network none -v dockerlab_orphaned_logs:/logs alpine:latest \
    sh -c 'dd if=/dev/urandom of=/logs/old.log bs=1M count=10 status=none'

echo
echo "Done. Lab dockerd is running on $SOCK with data-root $MNT."
echo
echo "Try:"
echo "  df -h $MNT"
echo "  sudo docker -H unix://$SOCK system df"
echo "  sudo docker -H unix://$SOCK system df -v"
echo
echo "To clean up later, see reset.sh."
