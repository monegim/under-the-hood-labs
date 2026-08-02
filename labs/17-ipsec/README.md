# Lab 17 — IPsec

## Objective
Build a site-to-site IPsec tunnel between two gateways with strongSwan,
protecting traffic between two LAN subnets, and prove the traffic is
actually encrypted on the wire.

## Why this matters
This is the real mechanism behind every "site-to-site VPN" you've clicked
"connect" on in a cloud console (AWS Site-to-Site VPN, Azure VPN Gateway,
GCP Cloud VPN are all IPsec under the hood) and behind most corporate
office-to-office/office-to-datacenter VPNs. Production IPsec outages almost
always come down to two things: a secret or algorithm mismatch between the
two ends, and forgetting to actually define which subnets the tunnel is
supposed to protect. Both are in this lab.

We use strongSwan with a pre-shared key (`ipsec.conf`/`ipsec.secrets`),
policy-based (not route-based/VTI) — the classic site-to-site pattern.

## Prerequisites
- Docker + [containerlab](https://containerlab.dev) installed
- `debian:bookworm-slim` image pulled

Check first:
```bash
docker version
containerlab version
docker pull debian:bookworm-slim
```

## Topology
```
hostA (10.1.1.10/24) -- r1 -- [underlay 172.16.0.0/30] -- r2 -- hostB (10.2.2.10/24)
```
r1 and r2 are the IPsec gateways. Traffic between `10.1.1.0/24` and
`10.2.2.0/24` gets encrypted across the underlay; the underlay link itself
carries only ESP.

## Step 1 — Deploy and install strongSwan
```bash
sudo containerlab deploy -t topology.clab.yml

for n in hostA hostB; do
  docker exec clab-ipsec-lab-$n bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump >/dev/null"
done

for n in r1 r2; do
  docker exec clab-ipsec-lab-$n bash -c \
    "apt-get update -qq && apt-get install -y -qq iproute2 iputils-ping tcpdump strongswan >/dev/null"
done
```
> This install takes a minute — strongSwan pulls in a fair number of
> dependencies.

## Step 2 — Address the interfaces
```bash
docker exec clab-ipsec-lab-hostA ip addr add 10.1.1.10/24 dev eth1
docker exec clab-ipsec-lab-hostA ip link set eth1 up
docker exec clab-ipsec-lab-hostA ip route add default via 10.1.1.1

docker exec clab-ipsec-lab-r1 ip addr add 10.1.1.1/24 dev eth1
docker exec clab-ipsec-lab-r1 ip link set eth1 up
docker exec clab-ipsec-lab-r1 ip addr add 172.16.0.1/30 dev eth2
docker exec clab-ipsec-lab-r1 ip link set eth2 up

docker exec clab-ipsec-lab-r2 ip addr add 172.16.0.2/30 dev eth1
docker exec clab-ipsec-lab-r2 ip link set eth1 up
docker exec clab-ipsec-lab-r2 ip addr add 10.2.2.1/24 dev eth2
docker exec clab-ipsec-lab-r2 ip link set eth2 up

docker exec clab-ipsec-lab-hostB ip addr add 10.2.2.10/24 dev eth1
docker exec clab-ipsec-lab-hostB ip link set eth1 up
docker exec clab-ipsec-lab-hostB ip route add default via 10.2.2.1

docker exec clab-ipsec-lab-r1 sysctl -w net.ipv4.ip_forward=1
docker exec clab-ipsec-lab-r2 sysctl -w net.ipv4.ip_forward=1
```
Verify the underlay works, unencrypted, before touching IPsec:
```bash
docker exec clab-ipsec-lab-r1 ping -c 3 172.16.0.2
```

## Step 3 — Write the strongSwan config on r1
```bash
docker exec -i clab-ipsec-lab-r1 bash -c "cat > /etc/ipsec.conf" <<'EOF'
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

docker exec -i clab-ipsec-lab-r1 bash -c "cat > /etc/ipsec.secrets" <<'EOF'
172.16.0.1 172.16.0.2 : PSK "supersecretpsk"
EOF
```
> Gotcha: `leftsubnet`/`rightsubnet` are what actually protect the LAN-to-LAN
> traffic. Leave them out (defaulting to the gateway addresses themselves)
> and you'll get a tunnel that only protects traffic between r1 and r2
> directly — hostA-to-hostB traffic will just route past it in the clear.
> This is a very real production mistake.

## Step 4 — Write the mirrored config on r2
```bash
docker exec -i clab-ipsec-lab-r2 bash -c "cat > /etc/ipsec.conf" <<'EOF'
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

docker exec -i clab-ipsec-lab-r2 bash -c "cat > /etc/ipsec.secrets" <<'EOF'
172.16.0.2 172.16.0.1 : PSK "supersecretpsk"
EOF
```

## Step 5 — Start strongSwan and bring the tunnel up
```bash
docker exec clab-ipsec-lab-r1 ipsec start
docker exec clab-ipsec-lab-r2 ipsec start
sleep 2
docker exec clab-ipsec-lab-r1 ipsec up site-to-site
```

## Step 6 — Verify the SA
```bash
docker exec clab-ipsec-lab-r1 ipsec statusall
docker exec clab-ipsec-lab-r1 ip xfrm state
docker exec clab-ipsec-lab-r1 ip xfrm policy
```
You should see `site-to-site` as `ESTABLISHED`, an `IPsec SA established`
line, and matching `esp` transform state in `ip xfrm state`.

## Step 7 — Test it and prove it's actually encrypted
```bash
docker exec clab-ipsec-lab-hostA ping -c 3 10.2.2.10
```
Capture on the underlay — you should see ESP (IP protocol 50), never plain
ICMP:
```bash
docker exec clab-ipsec-lab-r1 tcpdump -ni eth2 -c 5 esp
```

## Challenges

**Challenge A:**
```bash
docker exec clab-ipsec-lab-r2 sed -i 's/supersecretpsk/wrongpsk/' /etc/ipsec.secrets
docker exec clab-ipsec-lab-r2 ipsec rereadsecrets
docker exec clab-ipsec-lab-r1 ipsec down site-to-site
docker exec clab-ipsec-lab-r1 ipsec up site-to-site
```
The tunnel fails to establish. Check `ipsec statusall` and the charon log
(`docker exec clab-ipsec-lab-r1 journalctl -u strongswan --no-pager -n 30`,
or check `/var/log/syslog` if `journalctl` isn't available in the
container) on both sides before concluding anything. Note exactly which
phase of the negotiation gets furthest before failing.

**Challenge B:**
```bash
docker exec clab-ipsec-lab-r2 sed -i 's/esp=aes256-sha256!/esp=aes128-sha1!/' /etc/ipsec.conf
docker exec clab-ipsec-lab-r2 ipsec reload
docker exec clab-ipsec-lab-r1 ipsec down site-to-site
docker exec clab-ipsec-lab-r1 ipsec up site-to-site
```
This also fails to establish, and looks similar to Challenge A at first
glance — "tunnel won't come up" either way. Read the log lines closely on
both sides and figure out what's actually different about *where* and
*why* this one fails, before you fix it.

See `SOLUTION.md` only after you've formed your own diagnosis.
