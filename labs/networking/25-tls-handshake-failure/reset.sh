#!/usr/bin/env bash
# Lab 25 (TLS Handshake Failure) - destroys and redeploys the topology,
# then re-applies addressing, cert generation, and the nginx vhost config
# from the README's Steps 1-9, ending at the healthy dual-version,
# broad-cipher end state (not the intentionally-narrow Step 4/8 states) -
# none of this is baked into the topology file.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLIENT="clab-tls-lab-client"
PROXY="clab-tls-lab-proxy"

echo "[reset] destroying existing topology (if any)..."
sudo containerlab destroy -t "$DIR/topology.clab.yml" --cleanup

echo "[reset] deploying topology fresh..."
sudo containerlab deploy -t "$DIR/topology.clab.yml"

echo "[reset] addressing the link..."
docker exec "$CLIENT" ip addr add 10.99.0.1/24 dev eth1
docker exec "$CLIENT" ip link set eth1 up
docker exec "$PROXY" ip addr add 10.99.0.2/24 dev eth1
docker exec "$PROXY" ip link set eth1 up

echo "[reset] installing openssl on proxy..."
docker exec "$PROXY" sh -c "apt-get update -qq && apt-get install -y -qq openssl >/dev/null"

echo "[reset] generating self-signed certificates..."
docker exec "$PROXY" mkdir -p /etc/nginx/certs
docker exec "$PROXY" openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /etc/nginx/certs/correct.key -out /etc/nginx/certs/correct.crt \
  -subj "/CN=correct.example.test"
docker exec "$PROXY" openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /etc/nginx/certs/other.key -out /etc/nginx/certs/other.crt \
  -subj "/CN=other.example.test"

echo "[reset] writing nginx vhost config (healthy end state: TLS 1.2+1.3, broad ciphers)..."
docker exec -i "$PROXY" bash -c "cat > /etc/nginx/conf.d/default.conf" <<'EOF'
server {
    listen 443 ssl default_server;
    server_name correct.example.test;

    ssl_certificate     /etc/nginx/certs/correct.crt;
    ssl_certificate_key /etc/nginx/certs/correct.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5:!3DES;

    location / { return 200 "ok - served by correct.example.test vhost\n"; }
}

server {
    listen 443 ssl;
    server_name other.example.test;

    ssl_certificate     /etc/nginx/certs/other.crt;
    ssl_certificate_key /etc/nginx/certs/other.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5:!3DES;

    location / { return 200 "ok - served by other.example.test vhost\n"; }
}
EOF

docker exec "$PROXY" nginx -s reload

echo "[reset] Lab 25 topology redeployed at the healthy end state."
echo "[reset] Run ./check.sh to verify, or replay Steps 4-9 manually to see each mismatch first."
