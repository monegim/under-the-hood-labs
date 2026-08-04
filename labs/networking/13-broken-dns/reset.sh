#!/usr/bin/env bash
# Lab 13 (Broken DNS) — destroys and redeploys the topology, then re-runs
# the README's Steps 1-4 live config (package install, addressing,
# dnsmasq on resolver + upstream, client resolv.conf) — none of this is
# baked into the topology file.
set -uo pipefail

LAB="broken-dns"
CLIENT="clab-${LAB}-client"
RESOLVER="clab-${LAB}-resolver"
UPSTREAM="clab-${LAB}-upstream"

cd "$(dirname "$0")"

echo "[reset] destroying existing topology (if any)..."
sudo containerlab destroy -t topology.clab.yml --cleanup

echo "[reset] deploying topology..."
sudo containerlab deploy -t topology.clab.yml

echo "[reset] waiting for nodes to be ready..."
for c in "$CLIENT" "$RESOLVER" "$UPSTREAM"; do
  ready=0
  for i in $(seq 1 30); do
    docker exec "$c" true >/dev/null 2>&1 && { ready=1; break; }
    sleep 2
  done
  [ "$ready" -eq 1 ] || { echo "[reset] ERROR: $c never became ready"; exit 1; }
done

echo "[reset] installing tools (this can take a minute)..."
for n in "$CLIENT" "$RESOLVER" "$UPSTREAM"; do
  docker exec "$n" bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping dnsmasq dnsutils >/dev/null"
done

echo "[reset] addressing interfaces..."
docker exec "$CLIENT" ip addr add 10.0.1.10/24 dev eth1
docker exec "$CLIENT" ip link set eth1 up

docker exec "$RESOLVER" ip addr add 10.0.1.1/24 dev eth1
docker exec "$RESOLVER" ip link set eth1 up
docker exec "$RESOLVER" ip addr add 10.0.2.1/24 dev eth2
docker exec "$RESOLVER" ip link set eth2 up

docker exec "$UPSTREAM" ip addr add 10.0.2.2/24 dev eth1
docker exec "$UPSTREAM" ip link set eth1 up

echo "[reset] starting upstream dnsmasq (authoritative for app.internal)..."
docker exec -d "$UPSTREAM" dnsmasq -k --no-resolv --no-hosts \
  --address=/app.internal/10.9.9.99 --local-ttl=20 \
  --listen-address=10.0.2.2 --bind-interfaces

echo "[reset] starting resolver dnsmasq (pure forwarder)..."
docker exec -d "$RESOLVER" dnsmasq -k --no-resolv \
  --server=10.0.2.2 --listen-address=10.0.1.1 --bind-interfaces --cache-size=150

echo "[reset] pointing client at the resolver..."
docker exec "$CLIENT" bash -c "echo 'nameserver 10.0.1.1' > /etc/resolv.conf"

sleep 1
echo "[reset] verifying resolution..."
if docker exec "$CLIENT" dig +short +time=3 app.internal | grep -q "10.9.9.99"; then
  echo "[reset] app.internal resolves correctly"
else
  echo "[reset] WARNING: app.internal did not resolve as expected, check manually"
fi

echo "[reset] done. Run ./check.sh to verify health."
