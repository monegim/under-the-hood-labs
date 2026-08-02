# Lab 9 — VLANs

## Objective
Build two VLANs on one shared Linux bridge, prove they're isolated from
each other despite sharing the same physical/bridge infrastructure, then
add a trunk port and see 802.1q tags with your own eyes.

## Why this matters
Every managed switch's "access port" / "trunk port" / "native VLAN"
configuration maps directly onto Linux bridge VLAN filtering. This is what
VLAN-aware bridges in Open vSwitch do, what Kubernetes multus/SR-IOV VLAN
plugins configure under the hood, and exactly what you're troubleshooting
when a hypervisor NIC's `.10` sub-interface (`eth0.10`) shows up in `ip a`.

## Prerequisites
- Linux VM with `iproute2` (`ip`, `bridge`)
- `8021q` kernel module
- `sudo` access

Check first:
```bash
ip -V
which bridge
sudo modprobe 8021q && lsmod | grep 8021q
```

## Step 1 — Build a VLAN-aware bridge
```bash
sudo ip link add name br0 type bridge vlan_filtering 1
sudo ip link set br0 up
bridge vlan show dev br0
```
> Gotcha: `vlan_filtering 1` has to be set (at creation, or toggled after
> with `ip link set br0 type bridge vlan_filtering 1`). A plain bridge
> silently ignores 802.1q tags and just switches everything as one flat
> broadcast domain — no errors, it just doesn't do what you think it does.

## Step 2 — Create 4 namespaces, two per VLAN
```bash
for ns in ns1 ns2 ns3 ns4; do
  sudo ip netns add $ns
done
```
`ns1`/`ns2` will be VLAN 10 ("prod"), `ns3`/`ns4` will be VLAN 20 ("dev").

## Step 3 — Wire each namespace to the bridge as an access port
```bash
for n in 1 2 3 4; do
  sudo ip link add veth$n type veth peer name veth$n-br
  sudo ip link set veth$n netns ns$n
  sudo ip link set veth$n-br master br0
  sudo ip link set veth$n-br up
  sudo ip netns exec ns$n ip link set veth$n up
  sudo ip netns exec ns$n ip link set lo up
done

sudo ip netns exec ns1 ip addr add 10.10.0.1/24 dev veth1
sudo ip netns exec ns2 ip addr add 10.10.0.2/24 dev veth2
sudo ip netns exec ns3 ip addr add 10.20.0.1/24 dev veth3
sudo ip netns exec ns4 ip addr add 10.20.0.2/24 dev veth4
```

## Step 4 — Assign VLANs to the access ports
Every port lands in the bridge's default VLAN 1 the moment you enslave it.
Remove that and set the real access VLAN + PVID:
```bash
for n in 1 2; do
  sudo bridge vlan del dev veth$n-br vid 1
  sudo bridge vlan add dev veth$n-br vid 10 pvid untagged
done
for n in 3 4; do
  sudo bridge vlan del dev veth$n-br vid 1
  sudo bridge vlan add dev veth$n-br vid 20 pvid untagged
done
bridge vlan show
```
`pvid untagged` = access port behavior: untagged frames coming in get
tagged internally with this VLAN, and frames going out have the tag
stripped. Exactly what a switch access port does.

## Step 5 — Prove isolation
```bash
sudo ip netns exec ns1 ping -c 2 10.10.0.2   # ns1 -> ns2, same VLAN, works
sudo ip netns exec ns1 ping -c 2 10.20.0.1   # ns1 -> ns3, different VLAN
```
The second ping times out. ns1 and ns3 aren't just on different subnets —
they aren't even in the same broadcast domain, despite being plugged into
the exact same bridge device.

## Step 6 — Add a trunk port and watch tags on the wire
Attach a 5th veth as a trunk port carrying both VLANs, tagged, into a
"router" namespace:
```bash
sudo ip netns add router
sudo ip link add veth5 type veth peer name veth5-br
sudo ip link set veth5 netns router
sudo ip link set veth5-br master br0
sudo ip link set veth5-br up
sudo ip netns exec router ip link set veth5 up
sudo ip netns exec router ip link set lo up
```
Make the bridge port a trunk — tagged member of both VLANs, no PVID:
```bash
sudo bridge vlan del dev veth5-br vid 1
sudo bridge vlan add dev veth5-br vid 10
sudo bridge vlan add dev veth5-br vid 20
bridge vlan show dev veth5-br
```
No `pvid untagged` this time — both entries are tagged, so this port
expects/sends 802.1q-tagged frames for both VLANs. That's a trunk.

Inside the router namespace, create VLAN sub-interfaces (router-on-a-stick):
```bash
sudo ip netns exec router ip link add link veth5 name veth5.10 type vlan id 10
sudo ip netns exec router ip link add link veth5 name veth5.20 type vlan id 20
sudo ip netns exec router ip addr add 10.10.0.254/24 dev veth5.10
sudo ip netns exec router ip addr add 10.20.0.254/24 dev veth5.20
sudo ip netns exec router ip link set veth5.10 up
sudo ip netns exec router ip link set veth5.20 up
sudo ip netns exec router ip link set veth5 up
```
The router now has one wire (`veth5`) carrying two tagged VLANs — exactly
like a router-on-a-stick uplink into a switch trunk port.
```bash
sudo ip netns exec router ping -c 2 10.10.0.1   # reaches ns1 over the trunk
sudo ip netns exec router ping -c 2 10.20.0.1   # reaches ns3, same wire, different tag
```
See the tag itself:
```bash
sudo ip netns exec router tcpdump -i veth5 -e -n -c 4 &
sudo ip netns exec router ping -c 2 10.10.0.1
```
`tcpdump -e` prints the frame's VLAN tag — the same 802.1q header a NIC
driver or top-of-rack switch parses on every frame.

## Challenges

**Challenge A:**
```bash
sudo bridge vlan del dev veth2-br vid 10
sudo bridge vlan add dev veth2-br vid 20 pvid untagged
```
`ns2` was VLAN 10 and could reach `ns1`. Something's changed about who it
can and can't reach. Use `bridge vlan show` to see exactly what moved —
don't just guess from ping results.

**Challenge B:**
```bash
sudo bridge vlan del dev veth5-br vid 20
```
Traffic to one VLAN over the trunk breaks; the other keeps working fine.
This is one of the most common trunk-port mistakes in real switch configs —
figure out which side (the bridge trunk port, or the router's
sub-interface) is still expecting VLAN 20, and which one silently stopped
carrying it.

See `SOLUTION.md` only after you've formed your own diagnosis.
