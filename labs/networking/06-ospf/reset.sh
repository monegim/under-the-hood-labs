#!/usr/bin/env bash
set -uo pipefail

# Lab 6 - OSPF: destroy and redeploy the containerlab topology, then
# re-enable ospfd and re-apply addressing/OSPF config from the README's
# build steps (Steps 2-4) - none of this is baked into the topology
# file, it's all applied live via docker exec/vtysh.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[reset] destroying existing topology (if any)..."
sudo clab destroy -t "$DIR/topology.clab.yml" --cleanup

echo "[reset] deploying topology fresh..."
sudo clab deploy -t "$DIR/topology.clab.yml"

echo "[reset] enabling ospfd on each router..."
for r in r1 r2 r3; do
  docker exec clab-ospf-$r sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
  docker exec clab-ospf-$r /usr/lib/frr/frrinit.sh restart
done

echo "[reset] addressing hosts..."
docker exec clab-ospf-host1 ip addr add 10.0.1.10/24 dev eth1
docker exec clab-ospf-host1 ip link set eth1 up
docker exec clab-ospf-host1 ip route add default via 10.0.1.1

docker exec clab-ospf-host2 ip addr add 10.0.3.10/24 dev eth1
docker exec clab-ospf-host2 ip link set eth1 up
docker exec clab-ospf-host2 ip route add default via 10.0.3.1

echo "[reset] configuring interfaces and OSPF on the routers..."
docker exec clab-ospf-r1 vtysh \
  -c "conf t" \
  -c "interface eth1" -c "ip address 10.0.1.1/24" -c "exit" \
  -c "interface eth2" -c "ip address 10.0.12.1/30" -c "exit" \
  -c "router ospf" -c "ospf router-id 1.1.1.1" \
  -c "network 10.0.1.0/24 area 0" -c "network 10.0.12.0/30 area 0"

docker exec clab-ospf-r2 vtysh \
  -c "conf t" \
  -c "interface eth1" -c "ip address 10.0.12.2/30" -c "exit" \
  -c "interface eth2" -c "ip address 10.0.23.1/30" -c "exit" \
  -c "router ospf" -c "ospf router-id 2.2.2.2" \
  -c "network 10.0.12.0/30 area 0" -c "network 10.0.23.0/30 area 0"

docker exec clab-ospf-r3 vtysh \
  -c "conf t" \
  -c "interface eth1" -c "ip address 10.0.23.2/30" -c "exit" \
  -c "interface eth2" -c "ip address 10.0.3.1/24" -c "exit" \
  -c "router ospf" -c "ospf router-id 3.3.3.3" \
  -c "network 10.0.23.0/30 area 0" -c "network 10.0.3.0/24 area 0"

echo "[reset] Lab 6 topology redeployed and configured fresh"
