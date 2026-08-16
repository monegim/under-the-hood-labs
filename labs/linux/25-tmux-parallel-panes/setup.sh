#!/usr/bin/env bash
# Lab 25 setup — simulates three "hosts" as three directories, each
# with a version.txt and a restart.log. host2 has silently drifted to
# an older version; host1 and host3 are correct. Nothing is running in
# the background — this lab is entirely about the workflow of watching
# and acting on all three at once (or deliberately NOT all three at
# once) via tmux panes, not about a live service.
set -euo pipefail

LABDIR=/var/tmp/lab25
rm -rf "$LABDIR"
mkdir -p "$LABDIR/host1" "$LABDIR/host2" "$LABDIR/host3"

echo "v2.3.1" > "$LABDIR/host1/version.txt"
echo "v2.1.0" > "$LABDIR/host2/version.txt"   # drifted — the one that needs fixing
echo "v2.3.1" > "$LABDIR/host3/version.txt"

: > "$LABDIR/host1/restart.log"
: > "$LABDIR/host2/restart.log"
: > "$LABDIR/host3/restart.log"

echo "[setup] checking for tmux..."
if ! command -v tmux >/dev/null 2>&1; then
    echo "[setup] installing tmux..."
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux
fi
tmux -V

echo "[setup] done. Three simulated hosts under $LABDIR/host{1,2,3}/ — one of them has drifted."
