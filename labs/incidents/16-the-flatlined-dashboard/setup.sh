#!/usr/bin/env bash
# Incident 16 setup - builds the entire broken environment:
#   - orders-api.service: a tiny HTTP service with a CPU-bound /work
#     endpoint, standing in for the real order API.
#   - metrics-agent.service: a background collector (threaded HTTP
#     server on :9100) that samples load + orders-api latency every 3s,
#     serves the latest snapshot at /metrics, and persists every
#     snapshot to an NFS-mounted path - the same "compliance wants
#     metrics durably stored off-box" requirement that shows up in real
#     shops running a homegrown collector in front of Prometheus.
#   - an NFS export/mount to localhost (same trick as
#     labs/linux/09-process-stuck-in-d-state), which the agent's
#     collector thread writes to on every sample.
#
# Fault injection, in order (this is the story, not something you do):
#   1. A CPU-hungry background job starts on the box (a "log
#      reindexing" cron job someone scheduled, modeled here as a set of
#      busy-loop processes) - orders-api's real latency starts
#      climbing for real, because it now has to fight for CPU time.
#   2. Moments later, the NFS path the metrics agent depends on for
#      durability goes unreachable (iptables DROP on port 2049, same
#      mechanism as linux/09 and incident 05). The agent's collector
#      thread was mid-write when this happened and blocks in the
#      kernel (D state) - it never returns to take another sample.
#      Because the HTTP server that answers /metrics runs on a
#      *different* thread in the same process, it keeps answering
#      requests instantly - just with whatever snapshot was cached
#      right before the write blocked. That snapshot was captured
#      while the CPU hog was still spinning up, so it looks perfectly
#      healthy, and it will keep looking perfectly healthy forever.
set -euo pipefail

echo "[1/9] Installing NFS server/client tools..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nfs-kernel-server nfs-common iptables python3 python3-pip curl >/dev/null

echo "[2/9] Exporting /srv/metricslab to ourselves over NFS..."
sudo mkdir -p /srv/metricslab
sudo chmod 777 /srv/metricslab
if ! grep -q "^/srv/metricslab " /etc/exports 2>/dev/null; then
    echo "/srv/metricslab 127.0.0.1(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports >/dev/null
fi
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server

echo "[3/9] Mounting it as a HARD mount at /mnt/metricslab (matches production durability requirements - a 'soft' mount would silently drop samples on timeout instead of blocking)..."
sudo mkdir -p /mnt/metricslab
if ! mountpoint -q /mnt/metricslab; then
    sudo mount -t nfs -o hard,intr 127.0.0.1:/srv/metricslab /mnt/metricslab
fi
sudo chmod 777 /mnt/metricslab

echo "[4/9] Deploying orders-api (CPU-bound /work endpoint, instant /health)..."
sudo tee /usr/local/bin/orders-api.py > /dev/null <<'PYEOF'
#!/usr/bin/env python3
"""Stand-in order API. /work does a fixed amount of real CPU work, the
same shape as request handling in a real service (serialization,
validation, hashing, etc.) - its wall-clock time is a direct, honest
reading of how much CPU time this box can actually give it right now."""
import hashlib
import http.server

ITERATIONS = 300_000


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = b'{"status":"ok"}'
        elif self.path == "/work":
            h = hashlib.sha256(b"orders-api")
            for _ in range(ITERATIONS):
                h.update(h.digest())
            body = b'{"status":"ok"}'
        else:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


http.server.ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
PYEOF
sudo chmod +x /usr/local/bin/orders-api.py

sudo tee /etc/systemd/system/orders-api.service > /dev/null <<'EOF'
[Unit]
Description=Orders API (Incident 16)
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/orders-api.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

echo "[5/9] Deploying metrics-agent (collector thread + /metrics HTTP thread, same process)..."
sudo tee /usr/local/bin/metrics-agent.py > /dev/null <<'PYEOF'
#!/usr/bin/env python3
"""
Samples system load + orders-api /work latency every 3s and persists
each sample to /mnt/metricslab/metrics.json for durability (an NFS
hard mount). Serves the *last successfully persisted* sample at
GET /metrics on :9100 from a separate thread.

This is deliberately not fancy: the collector loop does real work
(open/write/fsync/close against the NFS mount) using a normal blocking
syscall. If that syscall blocks in the kernel, this thread stops
making progress - but the HTTP thread serving /metrics is a *different*
thread in the same process, so it keeps answering scrapes immediately,
forever, with the last value the collector managed to write before it
got stuck. Nothing here crashes. Nothing here logs an error. It just
stops updating.
"""
import http.server
import json
import os
import threading
import time
import urllib.request

METRICS_PATH = "/mnt/metricslab/metrics.json"
last_good = {"timestamp": 0, "load1": 0.0, "work_latency_ms": 0}
lock = threading.Lock()


def sample_load1():
    with open("/proc/loadavg") as f:
        return float(f.read().split()[0])


def sample_work_latency_ms():
    start = time.time()
    try:
        urllib.request.urlopen("http://localhost:8080/work", timeout=10).read()
    except Exception:
        return -1
    return round((time.time() - start) * 1000, 1)


def collector_loop():
    global last_good
    while True:
        snapshot = {
            "timestamp": int(time.time()),
            "load1": sample_load1(),
            "work_latency_ms": sample_work_latency_ms(),
        }
        # Durability write - this is the syscall that blocks (D state)
        # once the NFS path is unreachable.
        tmp_fd = os.open(METRICS_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
        os.write(tmp_fd, json.dumps(snapshot).encode())
        os.fsync(tmp_fd)
        os.close(tmp_fd)
        # Only reachable once the write above returns - this is exactly
        # why last_good freezes at whatever it was before the mount hung.
        with lock:
            last_good = snapshot
        time.sleep(3)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        with lock:
            body = json.dumps(last_good).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


threading.Thread(target=collector_loop, daemon=True).start()
http.server.ThreadingHTTPServer(("0.0.0.0", 9100), Handler).serve_forever()
PYEOF
sudo chmod +x /usr/local/bin/metrics-agent.py

sudo tee /etc/systemd/system/metrics-agent.service > /dev/null <<'EOF'
[Unit]
Description=Metrics agent (Incident 16)
After=network.target remote-fs.target orders-api.service

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/metrics-agent.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

echo "[6/9] Starting orders-api and metrics-agent, letting a healthy baseline settle..."
sudo systemctl daemon-reload
sudo systemctl enable --now orders-api.service
sleep 2
sudo systemctl enable --now metrics-agent.service
sleep 8
echo "      baseline /metrics:"
curl -s http://localhost:9100/metrics; echo

echo "[7/9] Starting the CPU-hungry background job (a 'log reindexing' cron job someone scheduled onto this box)..."
NPROC=$(nproc)
sudo mkdir -p /var/lib/metricslab
for i in $(seq 1 "$NPROC"); do
    nohup python3 -c 'x=0
while True: x = (x*1103515245+12345) % 2**31' >/var/lib/metricslab/hog-$i.log 2>&1 &
    echo $! | sudo tee -a /var/lib/metricslab/hog.pids >/dev/null
done
echo "      ${NPROC} CPU-hog processes started (pids in /var/lib/metricslab/hog.pids)"

echo "[8/9] Waiting for the hog to bite into real latency..."
sleep 5
echo "      orders-api /work is now genuinely slower:"
curl -s -w '  wall time: %{time_total}s\n' -o /dev/null http://localhost:8080/work

echo "[9/9] Cutting the NFS path (a flaky storage backend) - freezing the agent's next sample mid-write..."
sudo iptables -A OUTPUT -p tcp --dport 2049 -j DROP
sudo iptables -A INPUT -p tcp --sport 2049 -j DROP

sleep 4
echo
echo "Done. The incident is already live:"
echo "  curl -s -w '\ntime: %{time_total}s\n' http://localhost:8080/work    # genuinely slow"
echo "  curl -s http://localhost:9100/metrics                              # looks healthy, frozen"
echo "  date +%s                                                            # compare against the 'timestamp' field above"
