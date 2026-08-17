#!/usr/bin/env bash
set -euo pipefail

# Lab 31 setup: HAProxy load-balancing across three backends. All
# three answer /healthz (proves the process is alive) - HAProxy's
# health check only ever calls that path. backend3's *actual* work
# (/api/data) is broken. HAProxy has no way to know that, so it keeps
# sending it roughly a third of all real traffic, forever.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[setup] writing the broken haproxy.cfg (health check hits /healthz, not /api/data)..."
cat > haproxy/haproxy.cfg <<'EOF'
global
    log stdout format raw local0

defaults
    log     global
    mode    http
    timeout connect 3s
    timeout client  10s
    timeout server  10s

frontend fe_main
    bind *:8080
    default_backend be_apps

backend be_apps
    balance roundrobin
    option httpchk GET /healthz
    http-check expect status 200
    server backend1 backend1:5000 check
    server backend2 backend2:5000 check
    server backend3 backend3:5000 check

listen stats
    bind *:8404
    stats enable
    stats uri /
    stats refresh 5s
EOF

echo "[setup] building and starting backend1, backend2, backend3, haproxy..."
docker compose up -d --build

echo "[setup] waiting for haproxy to accept connections..."
for i in $(seq 1 30); do
    curl -s -o /dev/null http://localhost:8091/api/data 2>/dev/null && break
    sleep 1
done

echo
echo "Done. Try:"
echo '  for i in $(seq 1 9); do curl -s -o /dev/null -w "%{http_code} " http://localhost:8091/api/data; done; echo'
echo "  open http://localhost:8405/ for HAProxy's own stats page"
