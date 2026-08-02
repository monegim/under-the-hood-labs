#!/usr/bin/env bash
set -uo pipefail

# Lab 3 - Static Routing: destroy and redeploy the containerlab topology,
# then re-apply the addressing and static routes from the README's build
# steps (Steps 2-4) - none of this is baked into the topology file, it's
# all applied live via docker exec/vtysh.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] destroying existing topology (if any)..."
sudo clab destroy -t "$DIR/topology.clab.yml" --cleanup

echo "[reset] deploying topology fresh..."
sudo clab deploy -t "$DIR/topology.clab.yml"

echo "[reset] addressing hosts..."
docker exec clab-static-routing-host1 ip addr add 10.0.1.10/24 dev eth1
docker exec clab-static-routing-host1 ip link set eth1 up
docker exec clab-static-routing-host1 ip route add default via 10.0.1.1

docker exec clab-static-routing-host2 ip addr add 10.0.2.10/24 dev eth1
docker exec clab-static-routing-host2 ip link set eth1 up
docker exec clab-static-routing-host2 ip route add default via 10.0.2.1

echo "[reset] addressing routers..."
docker exec clab-static-routing-r1 vtysh \
  -c "conf t" \
  -c "interface eth1" -c "ip address 10.0.1.1/24" -c "exit" \
  -c "interface eth2" -c "ip address 10.0.12.1/30" -c "exit"

docker exec clab-static-routing-r2 vtysh \
  -c "conf t" \
  -c "interface eth1" -c "ip address 10.0.12.2/30" -c "exit" \
  -c "interface eth2" -c "ip address 10.0.2.1/24" -c "exit"

echo "[reset] applying static routes on both routers..."
docker exec clab-static-routing-r1 vtysh -c "conf t" -c "ip route 10.0.2.0/24 10.0.12.2"
docker exec clab-static-routing-r2 vtysh -c "conf t" -c "ip route 10.0.1.0/24 10.0.12.1"

echo "[reset] Lab 3 topology redeployed and configured fresh"
