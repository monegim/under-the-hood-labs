#!/usr/bin/env bash
# Lab 23 setup — builds a stale cache directory (60,000 *.tmp files
# across 60 subdirectories, plus a root-owned "quarantine" subdirectory
# you won't be able to touch without sudo), and starts 8 runaway
# "worker" processes plus one unrelated process that also happens to
# have "worker" in its name — the trap for Challenge B.
set -euo pipefail

CACHE=/var/tmp/lab23-cache
WORKERS=/var/tmp/lab23-workers
IMPORTANT=/var/tmp/lab23-important

echo "[setup] cleaning up any previous run..."
pkill -f "$WORKERS/worker-" 2>/dev/null || true
pkill -f "$IMPORTANT/network-worker-monitor.sh" 2>/dev/null || true
sudo rm -rf "$CACHE" "$WORKERS" "$IMPORTANT"
mkdir -p "$WORKERS" "$IMPORTANT"

echo "[setup] generating 60,000 stale cache files across 60 subdirectories..."
python3 - "$CACHE" <<'PYEOF'
import os
import sys

cache = sys.argv[1]
for d in range(60):
    dirpath = os.path.join(cache, f"dir{d:03d}")
    os.makedirs(dirpath, exist_ok=True)
    for f in range(1000):
        path = os.path.join(dirpath, f"file{f:04d}.tmp")
        os.close(os.open(path, os.O_CREAT | os.O_WRONLY, 0o644))
print("wrote 60,000 files across 60 directories")
PYEOF

echo "[setup] creating a root-owned quarantine subdirectory (needs sudo to touch)..."
sudo mkdir -p "$CACHE/quarantine"
sudo touch "$CACHE"/quarantine/file{01..20}.tmp
sudo chown -R root:root "$CACHE/quarantine"
sudo chmod 700 "$CACHE/quarantine"

echo "[setup] writing worker scripts..."
for i in $(seq 1 8); do
  cat > "$WORKERS/worker-$i.sh" <<'EOF'
#!/bin/bash
sleep 999999
EOF
  chmod +x "$WORKERS/worker-$i.sh"
done

cat > "$IMPORTANT/network-worker-monitor.sh" <<'EOF'
#!/bin/bash
# NOT one of the runaway workers -- this is a real service. Its name
# just happens to also contain "worker".
sleep 999999
EOF
chmod +x "$IMPORTANT/network-worker-monitor.sh"

echo "[setup] starting the 8 runaway workers and the (unrelated) important process..."
for i in $(seq 1 8); do
  bash "$WORKERS/worker-$i.sh" &
  disown
done
bash "$IMPORTANT/network-worker-monitor.sh" &
disown

sleep 1
echo "[setup] done."
echo "[setup] $(find "$CACHE" -name '*.tmp' 2>/dev/null | wc -l) stale *.tmp files under $CACHE (quarantine/ needs sudo to see)"
echo "[setup] $(pgrep -fc "$WORKERS/worker-") runaway workers running, plus 1 unrelated process with 'worker' in its name."
