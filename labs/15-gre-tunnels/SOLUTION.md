# Lab 15 — Solutions

## Challenge A — wrong remote endpoint

**Check:**
```bash
docker exec clab-gre-lab-r1 ip -d tunnel show gre1
docker exec clab-gre-lab-r1 ip link show gre1
```
`gre1` still reports `UP`/`UNKNOWN` state and looks completely healthy at
the link level — but `ip -d tunnel show` reveals `remote 172.16.0.99`, an
address nothing in this topology owns.

```bash
docker exec clab-gre-lab-r2 tcpdump -ni eth1 -c 5 proto gre
```
Nothing arrives at r2 at all.

**Diagnosis:** GRE has no handshake, keepalive, or peer-reachability check
by default — it's a stateless encapsulation. The tunnel interface will
happily report itself as administratively up even when pointed at an
address that doesn't exist or isn't the real peer. r1 encapsulates every
packet routed into `gre1` and ships it toward `172.16.0.99`; since nothing
is there, the packets simply vanish. There's no error, no interface
state change, nothing — a true silent black hole.

**Fix:**
```bash
docker exec clab-gre-lab-r1 ip tunnel change gre1 remote 172.16.0.2
```

**Lesson:** an "UP" tunnel interface tells you nothing about whether the
remote endpoint is correct or reachable, unlike a physical link where
link-down is a strong, fast signal. For any stateless tunnel (GRE, plain
IPIP), you have to verify the actual `remote`/`local` addresses configured
and confirm with a capture on the far side — never trust interface state
alone.

---

## Challenge B — missing route into the tunnel

**Check:**
```bash
docker exec clab-gre-lab-r2 ip route get 10.1.1.10
```
Returns an immediate error (no route / `RTNETLINK answers: Network is
unreachable`) rather than a timeout.

```bash
docker exec clab-gre-lab-r1 tcpdump -ni eth2 -c 5 proto gre
```
This actually still shows encapsulated GRE traffic leaving r1 fine —
r1's side of the config wasn't touched. The break is purely on r2's return
path.

**Diagnosis:** the tunnel and encapsulation are completely fine in both
directions — r1 can still encapsulate and send. But r2 no longer has a
route telling it "10.1.1.0/24 is reachable via `gre1`," so when it needs to
route return traffic back toward hostA it fails the route lookup
immediately, locally, before anything is even sent. This is a fast, loud
failure (immediate "unreachable") — the opposite signature of Challenge A's
silent timeout.

**Fix:**
```bash
docker exec clab-gre-lab-r2 ip route add 10.1.1.0/24 via 192.168.100.1 dev gre1
```

**Lesson:** creating a tunnel interface only builds a path — it does not
make either side aware they should route traffic onto it. That's a
separate step (a route), and a missing route fails fast and loud (instant
"unreachable" from a local route lookup), while a broken encapsulation
endpoint fails silently (packets sent into the void, no error at all).
Those two very different symptoms point you at two very different layers
of the problem.
