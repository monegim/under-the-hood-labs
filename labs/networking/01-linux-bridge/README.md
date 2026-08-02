# Lab 1 — Linux Bridge

## Objective
Build a Linux bridge (a virtual switch), connect two namespaces to it with
veth pairs, and watch it forward traffic like a real L2 switch — MAC
learning included.

## Why this matters
`docker0`, every Kubernetes CNI bridge plugin, and Open vSwitch's kernel
datapath all sit on top of the same primitive: a Linux bridge device
switching frames between attached interfaces based on a learned MAC address
table. Understand this lab and you understand what `docker network create
--driver bridge` actually built for you.

## Prerequisites
- Linux VM with `iproute2` (`ip`, `bridge` commands)
- `sudo` access

Check first:
```bash
ip -V
which bridge
lsmod | grep -q bridge || sudo modprobe bridge
```

## Step 1 — Create the bridge
```bash
sudo ip link add name br0 type bridge
sudo ip link set br0 up
ip -d link show br0
```
> Gotcha: a freshly created bridge is DOWN by default, same as `lo` in a new
> namespace. Nothing forwards until you bring it up.

## Step 2 — Create two "hosts" and their cables
```bash
sudo ip netns add ns1
sudo ip netns add ns2

sudo ip link add veth1 type veth peer name veth1-br
sudo ip link add veth2 type veth peer name veth2-br

sudo ip link set veth1 netns ns1
sudo ip link set veth2 netns ns2
```

## Step 3 — Plug the host-side ends into the bridge
```bash
sudo ip link set veth1-br master br0
sudo ip link set veth2-br master br0
sudo ip link set veth1-br up
sudo ip link set veth2-br up
```
> Gotcha: `master br0` only enslaves the interface — it doesn't bring it up.
> This is the most common mistake when wiring a bridge by hand: `bridge link
> show` reports the port as attached, but it stays DOWN and nothing forwards.

## Step 4 — Address and bring up the namespace side
```bash
sudo ip netns exec ns1 ip addr add 10.0.0.1/24 dev veth1
sudo ip netns exec ns1 ip link set veth1 up
sudo ip netns exec ns1 ip link set lo up

sudo ip netns exec ns2 ip addr add 10.0.0.2/24 dev veth2
sudo ip netns exec ns2 ip link set veth2 up
sudo ip netns exec ns2 ip link set lo up
```

## Step 5 — Test it, then watch MAC learning happen
```bash
sudo ip netns exec ns1 ping -c 3 10.0.0.2
bridge fdb show br0
```
You'll see `veth1-br` and `veth2-br`'s MACs learned dynamically against
`br0` — this table is exactly what a real switch's CAM table does.

## Step 6 — Compare to docker0
```bash
ip -d link show docker0
bridge link show
```
Same device type, same `master`/bridge relationship — `docker0` is just a
Linux bridge like `br0`, created and wired up automatically by `dockerd`.

## Challenges

**Challenge A:**
```bash
sudo ip link set veth1-br down
```
ns1 can no longer reach ns2. This looks like the Linux track's Network
Namespaces lab (Challenge A), but the interface you need to check this
time is not inside a namespace at all.

**Challenge B:**
```bash
sudo ip link set br0 down
```
Both ports individually still show UP, yet nothing forwards at all. Check
`bridge link show` and `ip -d link show br0` and work out why bringing
every port up isn't enough.

See `SOLUTION.md` only after you've formed your own diagnosis.
