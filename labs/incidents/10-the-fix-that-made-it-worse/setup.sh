#!/usr/bin/env bash
# Incident 10 setup - builds the entire broken environment:
#   - backend.service: a small HTTP service with genuinely bounded
#     capacity (3 concurrent workers, ~0.3s of real work each - about
#     10 requests/second sustained). Nothing wrong lives in this file -
#     it's just a normal service with a normal, finite capacity.
#   - client-traffic.service: stands in for real production traffic -
#     periodic bursts of checkout attempts (a completely normal,
#     recurring pattern for a real storefront), each one retried up to
#     RETRIES times on failure, with zero backoff between attempts -
#     "retry immediately, up to a few times" is a very common default
#     in real HTTP client libraries.
#
# The fault: RETRIES was recently raised from 0 to 3, specifically to
# reduce user-visible errors during these routine traffic bursts. By
# the time this script finishes, client-traffic.service has been
# running with RETRIES=3 for a while and the incident is already live
# - recurring bursts that used to clear in about a second each are now
# taking several times longer to drain, and each burst starts
# overlapping with the next one before the previous one has finished.
set -euo pipefail

echo "[1/4] Installing python3..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 curl >/dev/null

echo "[2/4] Deploying backend (bounded capacity: 3 concurrent workers, ~10 req/s sustained)..."
sudo tee /usr/local/bin/backend.py > /dev/null <<'PYEOF'
#!/usr/bin/env python3
"""backend: a completely ordinary service with a completely ordinary,
finite capacity. Nothing wrong lives in this file."""
import http.server
import socketserver
import time
from concurrent.futures import ThreadPoolExecutor

WORK_TIME = 0.3
executor = ThreadPoolExecutor(max_workers=3)
request_count = [0]

def do_work():
    time.sleep(WORK_TIME)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        request_count[0] += 1
        if request_count[0] % 20 == 0:
            print(f"[backend] total requests received so far: {request_count[0]}", flush=True)
        future = executor.submit(do_work)
        future.result()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def log_message(self, *args):
        pass

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with Server(("0.0.0.0", 7001), Handler) as httpd:
    httpd.serve_forever()
PYEOF

echo "[3/4] Deploying client-traffic (real production traffic, with retry-on-failure)..."
sudo tee /usr/local/bin/client-traffic.py > /dev/null <<'PYEOF'
#!/usr/bin/env python3
"""client-traffic: stands in for real users hitting checkout. Fires a
burst of BURST_SIZE checkout attempts every BURST_INTERVAL seconds,
forever - a completely normal, recurring traffic pattern. Each failed
attempt retries immediately, up to RETRIES more times, with zero
backoff - a very common default in real HTTP client libraries."""
import http.client
import os
import threading
import time

BURST_SIZE = int(os.environ.get("BURST_SIZE", "15"))
BURST_INTERVAL = float(os.environ.get("BURST_INTERVAL", "2"))
RETRIES = int(os.environ.get("RETRIES", "0"))
CLIENT_TIMEOUT = float(os.environ.get("CLIENT_TIMEOUT", "1.0"))

lock = threading.Lock()
stats = {"logical_ok": 0, "logical_fail": 0, "attempts": 0}

def checkout_attempt():
    attempt = 0
    while True:
        attempt += 1
        with lock:
            stats["attempts"] += 1
        try:
            conn = http.client.HTTPConnection("127.0.0.1", 7001, timeout=CLIENT_TIMEOUT)
            conn.request("GET", "/")
            resp = conn.getresponse()
            code = resp.status
            resp.read()
            conn.close()
        except Exception:
            code = 0
        if code == 200:
            with lock:
                stats["logical_ok"] += 1
            return
        if attempt > RETRIES:
            with lock:
                stats["logical_fail"] += 1
            return

def report():
    while True:
        time.sleep(10)
        with lock:
            total = stats["logical_ok"] + stats["logical_fail"]
            if total == 0:
                continue
            rate = stats["logical_fail"] / total * 100
            print(f"[client-traffic] last 10s window (cumulative): "
                  f"{total} checkout attempts, {stats['logical_fail']} failed "
                  f"({rate:.0f}%), {stats['attempts']} total HTTP requests sent",
                  flush=True)

threading.Thread(target=report, daemon=True).start()

while True:
    burst = [threading.Thread(target=checkout_attempt) for _ in range(BURST_SIZE)]
    for t in burst:
        t.start()
    time.sleep(BURST_INTERVAL)
PYEOF

sudo tee /etc/systemd/system/backend.service > /dev/null <<'EOF'
[Unit]
Description=backend (Incident 10)
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/backend.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/client-traffic.service > /dev/null <<'EOF'
[Unit]
Description=client-traffic (Incident 10)
After=network.target backend.service

[Service]
Environment=RETRIES=3
Environment=BURST_SIZE=15
Environment=BURST_INTERVAL=2
Environment=CLIENT_TIMEOUT=1.0
ExecStart=/usr/bin/python3 /usr/local/bin/client-traffic.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now backend.service
sleep 1
sudo systemctl enable --now client-traffic.service

echo "[4/4] Letting the incident run for a bit so it's already visibly degraded..."
sleep 12

echo
echo "Done. Environment is up and the incident is already in progress."
echo "Try:"
echo "  sudo journalctl -u client-traffic -n 5 --no-pager"
echo "  sudo journalctl -u backend -n 5 --no-pager"
