#!/usr/bin/env bash
# Lab 28 setup — build a real "too many open files" (EMFILE) incident.
#
# We launch a small Python process that opens files in a loop and never
# closes them, under an artificially low file-descriptor limit (via
# `ulimit -n` for the shell that execs it — the same mechanism systemd's
# LimitNOFILE= and pam_limits use under the hood: both ultimately call
# setrlimit(RLIMIT_NOFILE) on the process before/at exec). This gives you
# a real EMFILE error to diagnose, without needing root or a real service.
set -euo pipefail

WORKDIR="/var/tmp/lab28"
mkdir -p "$WORKDIR"
rm -f "$WORKDIR"/junk_*.tmp "$WORKDIR"/out.log "$WORKDIR"/err.log "$WORKDIR"/hog.pid

cat > "$WORKDIR/fd_hog.py" <<'PYEOF'
import sys, time

fds = []
i = 0
try:
    while True:
        f = open(f"/var/tmp/lab28/junk_{i}.tmp", "w")
        fds.append(f)
        i += 1
except OSError as e:
    print(f"FAILED after opening {i} files: {e}", file=sys.stderr)
    sys.stderr.flush()
    # hold everything open so you have time to diagnose the running process
    time.sleep(3600)
PYEOF

echo "[setup] starting fd_hog.py with an artificially low soft limit (ulimit -n 64)..."
( ulimit -n 64; exec python3 "$WORKDIR/fd_hog.py" ) >"$WORKDIR/out.log" 2>"$WORKDIR/err.log" &
HOGPID=$!
echo "$HOGPID" > "$WORKDIR/hog.pid"

sleep 2
echo "[setup] hog PID: $HOGPID"
echo "[setup] error output so far:"
cat "$WORKDIR/err.log" || true
echo
echo "[setup] investigate with:"
echo "    cat $WORKDIR/err.log"
echo "    ls -la /proc/$HOGPID/fd | wc -l"
echo "    grep -i 'open files' /proc/$HOGPID/limits"
echo "    lsof -p $HOGPID | wc -l"
echo "[setup] done. Process stays running (holding its fds) until you fix or kill it."
