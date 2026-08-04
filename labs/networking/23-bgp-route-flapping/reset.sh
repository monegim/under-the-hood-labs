#!/usr/bin/env bash
# Lab 23 (BGP Route Flapping) - tears down and redeploys the topology, then
# re-applies the addressing + eBGP config from the README's Steps 1-2
# (this config is applied live via vtysh, not baked into the topology
# file - only the /etc/frr/daemons bind mount is baked in). Dampening
# (Step 7) is intentionally NOT re-applied here - it's part of the lab's
# live walkthrough, not the baseline topology.
set -uo pipefail

LAB="bgp-flap-lab"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
R3="clab-${LAB}-r3"

cd "$(dirname "$0")"

echo "[reset] destroying existing topology (if any)..."
sudo containerlab destroy -t topology.clab.yml --cleanup

echo "[reset] deploying topology..."
sudo containerlab deploy -t topology.clab.yml

echo "[reset] waiting for routers to be ready (FRR/vtysh up)..."
for c in "$R1" "$R2" "$R3"; do
  ready=0
  for i in $(seq 1 30); do
    if docker exec "$c" vtysh -c "show version" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 2
  done
  [ "$ready" -eq 1 ] || { echo "[reset] ERROR: $c never became ready"; exit 1; }
done

echo "[reset] addressing interfaces (README Step 1)..."
docker exec "$R1" vtysh \
  -c "configure terminal" \
  -c "interface eth1" \
  -c "ip address 10.12.0.1/30" \
  -c "exit" \
  -c "interface lo" \
  -c "ip address 1.1.1.1/32" \
  -c "end" \
  -c "write memory"

docker exec "$R2" vtysh \
  -c "configure terminal" \
  -c "interface eth1" \
  -c "ip address 10.12.0.2/30" \
  -c "exit" \
  -c "interface eth2" \
  -c "ip address 10.23.0.1/30" \
  -c "exit" \
  -c "interface lo" \
  -c "ip address 2.2.2.2/32" \
  -c "end" \
  -c "write memory"

docker exec "$R3" vtysh \
  -c "configure terminal" \
  -c "interface eth1" \
  -c "ip address 10.23.0.2/30" \
  -c "exit" \
  -c "interface lo" \
  -c "ip address 3.3.3.3/32" \
  -c "end" \
  -c "write memory"

echo "[reset] configuring eBGP peering (README Step 2)..."
docker exec "$R1" vtysh \
  -c "configure terminal" \
  -c "router bgp 65001" \
  -c "bgp router-id 1.1.1.1" \
  -c "neighbor 10.12.0.2 remote-as 65002" \
  -c "address-family ipv4 unicast" \
  -c "redistribute connected" \
  -c "neighbor 10.12.0.2 activate" \
  -c "exit-address-family" \
  -c "end" \
  -c "write memory"

docker exec "$R2" vtysh \
  -c "configure terminal" \
  -c "router bgp 65002" \
  -c "bgp router-id 2.2.2.2" \
  -c "neighbor 10.12.0.1 remote-as 65001" \
  -c "neighbor 10.23.0.2 remote-as 65003" \
  -c "address-family ipv4 unicast" \
  -c "redistribute connected" \
  -c "neighbor 10.12.0.1 activate" \
  -c "neighbor 10.23.0.2 activate" \
  -c "exit-address-family" \
  -c "end" \
  -c "write memory"

docker exec "$R3" vtysh \
  -c "configure terminal" \
  -c "router bgp 65003" \
  -c "bgp router-id 3.3.3.3" \
  -c "neighbor 10.23.0.1 remote-as 65002" \
  -c "address-family ipv4 unicast" \
  -c "redistribute connected" \
  -c "neighbor 10.23.0.1 activate" \
  -c "exit-address-family" \
  -c "end" \
  -c "write memory"

echo "[reset] waiting for BGP sessions to establish..."
sleep 5

echo "[reset] done (no dampening configured yet - see README Step 7). Run ./check.sh to verify health."
