#!/usr/bin/env bash
# Lab 20 setup — builds a real zombie-accumulation incident: a parent
# process that forks children and never wait()s on them. No root needed.
set -euo pipefail

WORKDIR="/var/tmp/zombielab"
mkdir -p "$WORKDIR"
rm -f "$WORKDIR"/*.pid "$WORKDIR"/*.log

echo "[1/3] Writing the buggy parent (forks 20 children, never reaps them)..."
cat > "$WORKDIR/zombie_parent.py" <<'EOF'
#!/usr/bin/env python3
import os, time

print(f"parent: pid={os.getpid()}, forking 20 short-lived children, never calling wait()...", flush=True)
for i in range(20):
    pid = os.fork()
    if pid == 0:
        time.sleep(0.2)
        os._exit(0)
    time.sleep(0.05)

print(f"parent: pid={os.getpid()}, done forking. Children will pile up as zombies.", flush=True)
time.sleep(3600)
EOF

echo "[2/3] Starting it in the background..."
nohup python3 "$WORKDIR/zombie_parent.py" > "$WORKDIR/parent.log" 2>&1 &
PARENT_PID=$!
echo "$PARENT_PID" > "$WORKDIR/parent.pid"
disown

echo "[3/3] Waiting for the children to exit and pile up as zombies..."
sleep 3

echo
echo "Done. Parent PID: $PARENT_PID"
echo "Inspect with:"
echo "  ps -eo pid,ppid,stat,cmd | grep $PARENT_PID"
echo "  ps -eo pid,ppid,stat,cmd | awk '\$3 ~ /^Z/'"
