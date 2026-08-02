#!/usr/bin/env bash
# Lab 10 (IPsec) — tears down and redeploys the topology, then re-applies
# the README's Steps 1-6 live config (addressing, forwarding, strongSwan
# ipsec.conf/ipsec.secrets on both gateways, bringing the tunnel up) — none
# of this is baked into the topology file.
set -uo pipefail

LAB="ipsec-lab"
HOSTA="clab-${LAB}-hostA"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
HOSTB="clab-${LAB}-hostB"

cd "$(dirname "$0")"

echo "[reset] destroying existing topology (if any)..."
sudo containerlab destroy -t topology.clab.yml --cleanup

echo "[reset] deploying topology..."
sudo containerlab deploy -t topology.clab.yml

echo "[reset] waiting for nodes to be ready..."
for c in "$HOSTA" "$R1" "$R2" "$HOSTB"; do
  ready=0
  for i in $(seq 1 30); do
    docker exec "$c" true >/dev/null 2>&1 && { ready=1; break; }
    sleep 2
  done
  [ "$ready" -eq 1 ] || { echo "[reset] ERROR: $c never became ready"; exit 1; }
done

echo "[reset] installing strongSwan and tools (this can take a minute)..."
for n in hostA hostB; do
  docker exec "clab-${LAB}-$n" bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump >/dev/null"
done
for n in r1 r2; do
  docker exec "clab-${LAB}-$n" bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump strongswan >/dev/null"
done

echo "[reset] addressing interfaces..."
docker exec "$HOSTA" ip addr add 10.1.1.10/24 dev eth1
docker exec "$HOSTA" ip link set eth1 up
docker exec "$HOSTA" ip route add default via 10.1.1.1

docker exec "$R1" ip addr add 10.1.1.1/24 dev eth1
docker exec "$R1" ip link set eth1 up
docker exec "$R1" ip addr add 172.16.0.1/30 dev eth2
docker exec "$R1" ip link set eth2 up

docker exec "$R2" ip addr add 172.16.0.2/30 dev eth1
docker exec "$R2" ip link set eth1 up
docker exec "$R2" ip addr add 10.2.2.1/24 dev eth2
docker exec "$R2" ip link set eth2 up

docker exec "$HOSTB" ip addr add 10.2.2.10/24 dev eth1
docker exec "$HOSTB" ip link set eth1 up
docker exec "$HOSTB" ip route add default via 10.2.2.1

docker exec "$R1" sysctl -w net.ipv4.ip_forward=1
docker exec "$R2" sysctl -w net.ipv4.ip_forward=1

echo "[reset] writing strongSwan config on r1..."
docker exec -i "$R1" bash -c "cat > /etc/ipsec.conf" <<'EOF'
config setup
    charondebug="ike 2, esp 2"

conn site-to-site
    keyexchange=ikev2
    authby=secret
    left=172.16.0.1
    leftsubnet=10.1.1.0/24
    right=172.16.0.2
    rightsubnet=10.2.2.0/24
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256!
    keyingtries=0
    ikelifetime=1h
    keylife=20m
    auto=start
EOF

docker exec -i "$R1" bash -c "cat > /etc/ipsec.secrets" <<'EOF'
172.16.0.1 172.16.0.2 : PSK "supersecretpsk"
EOF

echo "[reset] writing the mirrored strongSwan config on r2..."
docker exec -i "$R2" bash -c "cat > /etc/ipsec.conf" <<'EOF'
config setup
    charondebug="ike 2, esp 2"

conn site-to-site
    keyexchange=ikev2
    authby=secret
    left=172.16.0.2
    leftsubnet=10.2.2.0/24
    right=172.16.0.1
    rightsubnet=10.1.1.0/24
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256!
    keyingtries=0
    ikelifetime=1h
    keylife=20m
    auto=start
EOF

docker exec -i "$R2" bash -c "cat > /etc/ipsec.secrets" <<'EOF'
172.16.0.2 172.16.0.1 : PSK "supersecretpsk"
EOF

echo "[reset] starting strongSwan and bringing the tunnel up..."
docker exec "$R1" ipsec start
docker exec "$R2" ipsec start
sleep 2
docker exec "$R1" ipsec up site-to-site

echo "[reset] verifying the SA and end-to-end connectivity..."
docker exec "$R1" ipsec statusall | grep -q "ESTABLISHED" \
  && echo "[reset] site-to-site SA is ESTABLISHED" \
  || echo "[reset] WARNING: site-to-site SA did not establish, check manually"

if docker exec "$HOSTA" ping -c 2 -W 2 10.2.2.10 >/dev/null 2>&1; then
  echo "[reset] hostA -> hostB reachable through the tunnel"
else
  echo "[reset] WARNING: hostA -> hostB ping failed, check manually"
fi

echo "[reset] done. Run ./check.sh to verify health."
