#!/usr/bin/env bash
# Incident 02 setup - builds the entire broken environment turnkey:
#   api -- r1 == (GRE tunnel over r1<->r2) == r2 -- db
#
# api runs a tiny report HTTP service that shells out to the real `mysql`
# CLI against db. r1/r2 emulate a WAN link carrying a GRE tunnel (same
# shape as labs/networking/11-mtu-issues). The fault injected here is the
# same one as that lab's Challenge A: r1 has an iptables rule silently
# dropping ICMP "fragmentation needed" - so Path MTU Discovery is
# blackholed for any TCP segment that doesn't fit the tunnel, and it's
# already in place before you start investigating.
set -euo pipefail

LAB="mtu-incident"
API="clab-${LAB}-api"
R1="clab-${LAB}-r1"
R2="clab-${LAB}-r2"
DB="clab-${LAB}-db"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "[1/8] Deploying containerlab topology..."
sudo containerlab deploy -t topology.clab.yml

echo "[2/8] Waiting for nodes to be ready..."
for c in "$API" "$R1" "$R2" "$DB"; do
    for i in $(seq 1 30); do
        docker exec "$c" true >/dev/null 2>&1 && break
        sleep 2
    done
done

echo "[3/8] Installing tools on api/r1/r2 (iproute2, iptables, tcpdump, mysql client)..."
docker exec "$API" bash -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iproute2 iputils-ping tcpdump iptables python3 mariadb-client curl >/dev/null"
for n in "$R1" "$R2"; do
    docker exec "$n" bash -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iproute2 iputils-ping tcpdump iptables >/dev/null"
done

echo "[4/8] Installing MariaDB server on db..."
docker exec "$DB" bash -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iproute2 iputils-ping tcpdump iptables mariadb-server procps >/dev/null"

echo "[5/8] Addressing interfaces and enabling forwarding..."
docker exec "$API" ip addr add 10.1.1.10/24 dev eth1
docker exec "$API" ip link set eth1 up
docker exec "$API" ip route add default via 10.1.1.1

docker exec "$R1" ip addr add 10.1.1.1/24 dev eth1
docker exec "$R1" ip link set eth1 up
docker exec "$R1" ip addr add 172.16.0.1/30 dev eth2
docker exec "$R1" ip link set eth2 up
docker exec "$R1" sysctl -w net.ipv4.ip_forward=1

docker exec "$R2" ip addr add 172.16.0.2/30 dev eth1
docker exec "$R2" ip link set eth1 up
docker exec "$R2" ip addr add 10.2.2.1/24 dev eth2
docker exec "$R2" ip link set eth2 up
docker exec "$R2" sysctl -w net.ipv4.ip_forward=1

docker exec "$DB" ip addr add 10.2.2.10/24 dev eth1
docker exec "$DB" ip link set eth1 up
docker exec "$DB" ip route add default via 10.2.2.1

echo "[6/8] Building the GRE tunnel between r1 and r2..."
docker exec "$R1" ip tunnel add gre1 mode gre remote 172.16.0.2 local 172.16.0.1 ttl 255
docker exec "$R1" ip addr add 192.168.100.1/30 dev gre1
docker exec "$R1" ip link set gre1 up
docker exec "$R1" ip route add 10.2.2.0/24 via 192.168.100.2 dev gre1

docker exec "$R2" ip tunnel add gre1 mode gre remote 172.16.0.1 local 172.16.0.2 ttl 255
docker exec "$R2" ip addr add 192.168.100.2/30 dev gre1
docker exec "$R2" ip link set gre1 up
docker exec "$R2" ip route add 10.1.1.0/24 via 192.168.100.1 dev gre1

echo "[7/8] Starting MariaDB on db and seeding data..."
docker exec "$DB" bash -c "mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld"
docker exec -d "$DB" bash -c "mysqld_safe --bind-address=0.0.0.0 >/var/log/mysqld_safe.log 2>&1"
for i in $(seq 1 30); do
    docker exec "$DB" mysqladmin ping >/dev/null 2>&1 && break
    sleep 2
done
docker cp seed.sql "$DB":/tmp/seed.sql
docker exec "$DB" bash -c "mysql -uroot < /tmp/seed.sql"

echo "[8/8] Deploying the report API on api and starting it..."
docker cp api_server.py "$API":/opt/api_server.py
docker exec -d "$API" python3 /opt/api_server.py
sleep 2

echo
echo "Injecting the fault: r1 drops outbound ICMP 'fragmentation needed'"
echo "(the on-call finds this already in place - a firewall hardening"
echo "change from last week, per the story, not something you just did)."
docker exec "$R1" iptables -A OUTPUT -p icmp --icmp-type fragmentation-needed -j DROP

echo
echo "Done. The incident is already live. Sanity checks:"
echo "  docker exec $API curl -s http://localhost:8000/health"
echo "  docker exec $API curl -s --max-time 15 'http://localhost:8000/report?customer_id=1'      # small customer - fine"
echo "  docker exec $API curl -s --max-time 15 'http://localhost:8000/report?customer_id=999'    # acme-corp - hangs"
