# Lab 1 — Network Namespaces

## Objective
Build two isolated "mini-networks" inside one Linux box, connect them with a
virtual cable, and understand the exact mechanism Docker/Kubernetes/containerlab
use under the hood.

## Why this matters
Every container networking tool (Docker, Kubernetes CNI, containerlab) is
built on network namespaces + veth pairs. If you understand this lab, you
understand what `docker0`, `kubectl exec`, and CNI plugins are actually doing —
it's not magic, it's just files and interfaces.

## Prerequisites
- Linux VM with `iproute2` installed
- `sudo` access

Check first:
```bash
uname -a
ip -V
which unshare nsenter
```

## Step 1 — Create two namespaces
```bash
sudo ip netns add ns1
sudo ip netns add ns2
ip netns list
```
Compare your normal network view to what's inside ns1:
```bash
ip a
sudo ip netns exec ns1 ip a
```
Notice ns1 only has a `lo` interface, and it's DOWN.

## Step 2 — Connect them with a virtual cable (veth pair)
A veth pair acts like an ethernet cable — whatever goes in one end comes out
the other.
```bash
sudo ip link add veth1 type veth peer name veth2
sudo ip link set veth1 netns ns1
sudo ip link set veth2 netns ns2
```

## Step 3 — Address and bring interfaces up
```bash
sudo ip netns exec ns1 ip addr add 10.0.0.1/24 dev veth1
sudo ip netns exec ns1 ip link set veth1 up
sudo ip netns exec ns1 ip link set lo up

sudo ip netns exec ns2 ip addr add 10.0.0.2/24 dev veth2
sudo ip netns exec ns2 ip link set veth2 up
sudo ip netns exec ns2 ip link set lo up
```
> Gotcha: `lo` comes up DOWN by default in every new namespace. This trips
> people up constantly — ping fails and it looks like a routing problem when
> it's actually just loopback being down.

## Step 4 — Test connectivity
```bash
sudo ip netns exec ns1 ping -c 3 10.0.0.2
```

## Step 5 — See it from the process side
```bash
sudo ip netns exec ns1 sleep 100 &
ls -la /proc/$!/ns/
```
That `net` symlink is literally how `docker exec` finds which network a
container belongs to.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A:**
```bash
sudo ip netns exec ns1 ip link set veth1 down
```
ns1 can no longer reach ns2. Check state first (`ip a`, `ip link`, `ip route`
inside the namespace) before touching anything. Fix it.

**Challenge B:**
```bash
sudo ip netns exec ns2 ip addr del 10.0.0.2/24 dev veth2
```
This looks similar to Challenge A but is a different failure mode. Figure out
what's different, and what evidence tells you which kind of problem you're
looking at.

See `SOLUTION.md` only after you've formed your own diagnosis.
