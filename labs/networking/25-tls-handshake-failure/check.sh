#!/usr/bin/env bash
# Lab 25 (TLS Handshake Failure) - verifies the proxy accepts both TLS 1.2
# and TLS 1.3 connections for correct.example.test (the healthy end state
# from README Steps 1-9: version mismatch and cipher mismatch both fixed).
set -uo pipefail

CLIENT="clab-tls-lab-client"
PROXY="clab-tls-lab-proxy"
PROXY_IP="10.99.0.2"

fail=0

echo "[check] verifying containers are running..."
for c in "$CLIENT" "$PROXY"; do
  status=$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)
  [ "$status" = "true" ] || { echo "[FAIL] container $c is not running (deploy the topology first)"; exit 1; }
done

echo "[check] nginx is listening on 443"
if ! docker exec "$PROXY" sh -c "nginx -t" >/dev/null 2>&1; then
  echo "[FAIL] nginx config test failed on proxy - check /etc/nginx/conf.d/default.conf"
  exit 1
fi

echo "[check] TLS 1.2 connection to correct.example.test"
if docker exec "$CLIENT" curl -k -s --max-time 5 --tlsv1.2 --tls-max 1.2 \
    --resolve "correct.example.test:443:${PROXY_IP}" \
    "https://correct.example.test/" -o /dev/null; then
  echo "[PASS] TLS 1.2 connection succeeded"
else
  echo "[FAIL] TLS 1.2 connection failed - check ssl_protocols/ssl_ciphers on the proxy"
  fail=1
fi

echo "[check] TLS 1.3 connection to correct.example.test"
if docker exec "$CLIENT" curl -k -s --max-time 5 --tlsv1.3 --tls-max 1.3 \
    --resolve "correct.example.test:443:${PROXY_IP}" \
    "https://correct.example.test/" -o /dev/null; then
  echo "[PASS] TLS 1.3 connection succeeded"
else
  echo "[FAIL] TLS 1.3 connection failed - check ssl_protocols on the proxy"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "[PASS] Lab 25 topology is healthy"
  exit 0
else
  echo "[FAIL] Lab 25 topology has issues (see above)"
  exit 1
fi
