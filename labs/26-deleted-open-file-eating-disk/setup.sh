#!/usr/bin/env bash
# Lab 26 setup — build the "df says full, du can't find it" incident.
#
# A long-running process (simulating a naive app/log writer) opens a file
# and keeps writing to it. We then `rm` the file out from under it, exactly
# like a cron-based `mv app.log app.log.1 && touch app.log` log rotation
# that never signals the app to reopen its log fd. The inode stays alive
# (and the disk space stays consumed) as long as the process holds the fd
# open, even though the file has no name anymore.
set -euo pipefail

WORKDIR="/var/tmp/lab26"
LOGFILE="$WORKDIR/app.log"

echo "[setup] creating workdir: $WORKDIR"
mkdir -p "$WORKDIR"
rm -f "$LOGFILE"

echo "[setup] starting writer process (writes 5MB chunks every 2 seconds)..."
# Simulates a chatty app writing to its log file forever. Kept slow on
# purpose so it doesn't actually fill a small lab VM's disk if you leave
# it running for a while — the point is to observe the mechanism, not to
# race the clock against real disk exhaustion.
nohup bash -c '
  exec 3>>"'"$LOGFILE"'"
  while true; do
    head -c 5242880 /dev/urandom >&3
    sleep 2
  done
' >"$WORKDIR/writer.out" 2>&1 &

WRITER_PID=$!
echo "$WRITER_PID" > "$WORKDIR/writer.pid"
echo "[setup] writer PID: $WRITER_PID"

echo "[setup] letting it write for a few seconds before rotating..."
sleep 5

echo "[setup] simulating a naive log rotation: rm the file the process still has open"
rm -f "$LOGFILE"

echo "[setup] file removed from the filesystem namespace, but writer PID $WRITER_PID"
echo "[setup] still holds it open — disk usage keeps climbing. Confirm with:"
echo
echo "    df -h $WORKDIR"
echo "    du -sh $WORKDIR"
echo "    ls -la $WORKDIR"
echo
echo "[setup] done. Writer keeps running in the background until you fix it or kill it."
