#!/usr/bin/env bash
# Incident 08 setup - builds the entire broken environment:
#   backend   - Flask, listening dual-stack on "::" (both IPv4 and
#               IPv6 reachable), on a Docker network with
#               enable_ipv6: true.
#   frontend  - Flask, calling backend's hostname via plain `requests`
#               (no Happy Eyeballs - resolves both an AAAA and an A
#               record, tries them in order, exactly like most default
#               HTTP client libraries).
#
# The fault: an ip6tables rule on backend silently DROPs (not rejects)
# incoming TCP to its app port over IPv6 only. ICMPv6 (ping) and IPv4
# both keep working fine - only this one port, over this one address
# family, goes silent. By the time this script finishes, the fault is
# already injected and /checkout is already slow - the incident is
# live, same as walking onto a real page.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[1/4] Building and starting backend, frontend..."
docker compose up -d --build

echo "[2/4] Waiting for backend to report healthy..."
for i in $(seq 1 30); do
    status=$(docker inspect --format='{{.State.Health.Status}}' incident08-backend 2>/dev/null || echo "starting")
    [ "$status" = "healthy" ] && break
    sleep 2
done

echo "[3/4] Waiting for frontend to answer /health..."
for i in $(seq 1 30); do
    curl -s -o /dev/null -w '%{http_code}' http://localhost:8090/health 2>/dev/null | grep -q 200 && break
    sleep 2
done

echo "[3/4] Confirming the baseline is fast..."
curl -s -X POST http://localhost:8090/checkout | head -c 200
echo

echo "[4/4] INJECTING THE FAULT: dropping IPv6 traffic to backend's app port..."
docker exec incident08-backend ip6tables -A INPUT -p tcp --dport 8080 -j DROP

echo
echo "Done. Environment is up and the incident is already in progress."
echo "  Frontend: http://localhost:8090"
echo
echo "Try:"
echo '  curl -s -w "\ntotal: %{time_total}s\n" -X POST http://localhost:8090/checkout'
