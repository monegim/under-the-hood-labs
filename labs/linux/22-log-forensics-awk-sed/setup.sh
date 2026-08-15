#!/usr/bin/env bash
# Lab 22 setup — generates 5 rotated-style access log files (75,000 lines
# total) covering a 2-hour window, with one IP silently responsible for
# 30% of all traffic, all of it hitting /api/search. Nothing is blocked
# yet — that's the reader's job, using awk/sed, not eyeballing files.
set -euo pipefail

LOGDIR=/var/tmp/lab22-logs
sudo rm -rf "$LOGDIR"
sudo mkdir -p "$LOGDIR"
sudo chown "$(id -u):$(id -g)" "$LOGDIR"

echo "[setup] generating synthetic access logs in $LOGDIR..."
python3 - "$LOGDIR" <<'PYEOF'
import random
import sys

logdir = sys.argv[1]
random.seed(1337)

NOISY_IP = "203.0.113.77"
NORMAL_IPS = [f"10.0.{a}.{b}" for a in range(1, 5) for b in range(1, 11)]  # 40 IPs
PATHS = ["/", "/api/products", "/api/cart", "/api/checkout", "/static/app.js", "/health"]
METHODS = ["GET", "GET", "GET", "POST"]

LINES_PER_FILE = 15000
FILES = 5
MINUTES_PER_FILE = 24  # 5 files * 24min = 120min = 2 hours total

def ts(file_index, minute_offset, second):
    base_minute = file_index * MINUTES_PER_FILE + minute_offset
    hour = 13 + base_minute // 60
    minute = base_minute % 60
    return f"2026-08-10T{hour:02d}:{minute:02d}:{second:02d}Z"

for f in range(FILES):
    path = f"{logdir}/access.log.{f + 1}"
    lines = []
    for i in range(LINES_PER_FILE):
        minute_offset = int((i / LINES_PER_FILE) * MINUTES_PER_FILE)
        second = i % 60
        timestamp = ts(f, minute_offset, second)
        if random.random() < 0.30:
            ip = NOISY_IP
            path_hit = "/api/search"
            status = 200
        else:
            ip = random.choice(NORMAL_IPS)
            path_hit = random.choice(PATHS)
            status = random.choice([200, 200, 200, 200, 404])
        method = random.choice(METHODS)
        size = random.randint(200, 8000)
        lines.append(f"{ip} {timestamp} {method} {path_hit} {status} {size}")
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"[setup] wrote {path} ({LINES_PER_FILE} lines)")

print("[setup] log generation done. Total lines:", LINES_PER_FILE * FILES)
PYEOF

echo "[setup] confirming no stale iptables rule exists for the noisy IP..."
sudo iptables -D INPUT -s 203.0.113.77 -j DROP 2>/dev/null || true

echo "[setup] done. Logs are in $LOGDIR — 5 files, ~15,000 lines each."
echo "[setup] The on-call channel says: 'app server under heavy load, check access logs.'"
