#!/usr/bin/env bash
# Incident 09 setup - builds the entire broken environment:
#   - service-a.service: a trivial, always-fast HTTP service on :6001 -
#     the actual critical service this page is about.
#   - service-b.service: an unrelated, lower-priority internal service
#     on :6002 whose one endpoint hangs indefinitely (standing in for
#     any backend that's stopped responding: a stuck dependency, a
#     deadlock, a downstream outage of its own).
#   - nginx, configured as a single shared reverse proxy in front of
#     BOTH services, on two different paths (/a/ and /b/) - a
#     deliberately small worker_connections limit so this reproduces
#     fast, matching the same shared-connection-pool mechanism a real,
#     much larger nginx/HAProxy instance has at a bigger scale.
#
# By the time this script finishes, several requests to service-b's
# hung endpoint are already in flight, holding nginx's connection pool
# near its ceiling - the incident is live, same as walking onto a real
# page.
set -euo pipefail

echo "[1/6] Installing nginx and python3..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx python3 curl >/dev/null

echo "[2/6] Deploying service-a (always fast, always healthy)..."
sudo tee /usr/local/bin/service-a.py > /dev/null <<'PYEOF'
#!/usr/bin/env python3
"""service-a: the actual critical service this page is about. Nothing
wrong lives in this file - every request answers instantly."""
import http.server
import socketserver

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"SERVICE-A-OK")

    def log_message(self, *args):
        pass

with socketserver.ThreadingTCPServer(("127.0.0.1", 6001), Handler) as httpd:
    httpd.serve_forever()
PYEOF

echo "[3/6] Deploying service-b (unrelated, and currently hung)..."
sudo tee /usr/local/bin/service-b.py > /dev/null <<'PYEOF'
#!/usr/bin/env python3
"""service-b: a completely separate, lower-priority internal service.
Its one endpoint is stuck - standing in for any backend that's stopped
responding (a stuck dependency, a deadlock, an outage of its own).
Nothing about service-a depends on service-b in any way."""
import http.server
import socketserver
import time

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(300)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"SERVICE-B-OK")

    def log_message(self, *args):
        pass

with socketserver.ThreadingTCPServer(("127.0.0.1", 6002), Handler) as httpd:
    httpd.serve_forever()
PYEOF

for svc in a b; do
sudo tee /etc/systemd/system/service-$svc.service > /dev/null <<EOF
[Unit]
Description=service-$svc (Incident 09)
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/service-$svc.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
done
sudo systemctl daemon-reload
sudo systemctl enable --now service-a.service service-b.service

echo "[4/6] Configuring nginx as a single shared proxy in front of both services..."
sudo tee /etc/nginx/nginx.conf > /dev/null <<'EOF'
worker_processes 1;
events {
    worker_connections 8;
}
http {
    server {
        listen 8080;

        location /a/ {
            proxy_pass http://127.0.0.1:6001/;
        }

        location /b/ {
            proxy_pass http://127.0.0.1:6002/;
        }
    }
}
EOF
sudo nginx -t
sudo systemctl restart nginx

echo "[5/6] Waiting for everything to come up..."
for i in $(seq 1 15); do
    curl -s -o /dev/null http://127.0.0.1:8080/a/ 2>/dev/null && break
    sleep 1
done

echo "[6/6] INJECTING THE FAULT: sending several concurrent requests into service-b's hung endpoint..."
for i in 1 2 3 4 5 6; do
    curl -s -m 60 http://127.0.0.1:8080/b/ -o /dev/null &
    disown
done
sleep 2

echo
echo "Done. Environment is up and the incident is already in progress."
echo "Try:"
echo '  curl -s -m 3 -o /dev/null -w "%{http_code} (%{time_total}s)\n" http://127.0.0.1:8080/a/'
