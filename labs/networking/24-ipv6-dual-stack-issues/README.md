# Lab 24 — IPv6 Dual-Stack Issues

## Objective
Build a dual-stack (IPv4 + IPv6) client/server pair, silently break only
the IPv6 path to one service port while leaving IPv6 reachability
otherwise intact, and see why a *half*-broken IPv6 path causes worse user-
facing symptoms than IPv6 being fully absent would.

## Why this matters
Happy Eyeballs (RFC 8305) exists because dual-stack clients need a
sensible way to pick between two address families without making users
wait. A well-behaved client (like `curl`) races IPv4 and IPv6 and just uses
whichever connects first, so a *fully broken* IPv6 path costs almost
nothing — the IPv4 attempt wins quickly regardless. A *partially* broken
IPv6 path — reachable at the network layer, silently dropped at the
service port — is a worse problem in practice: it still exists in DNS, it
still gets tried on every single connection, and any client that doesn't
implement Happy Eyeballs (or implements it with a badly tuned timeout)
pays the full price of that broken attempt before ever touching IPv4.

## Prerequisites
- Linux VM with `iproute2`, `python3`, `curl` (a recent version with
  `--resolve` and `--happy-eyeballs-timeout-ms` support), and `bash`
- `sudo` access

Check first:
```bash
ip -V
curl --version | head -1
python3 --version
```

## Step 1 — Build the topology
```bash
bash setup.sh
```
This creates `client` (`10.0.0.1` / `fd00::1`) and `server`
(`10.0.0.2` / `fd00::2`) namespaces on one veth link, and starts two
independent `python3 -m http.server` processes on the server — one bound
to the IPv4 address, one bound to the IPv6 address, both on port 80.

## Step 2 — Confirm both stacks work independently
```bash
sudo ip netns exec client ping -c 2 10.0.0.2
sudo ip netns exec client ping6 -c 2 fd00::2
sudo ip netns exec client curl -4 -s -o /dev/null -w "IPv4 time_total: %{time_total}s\n" http://10.0.0.2/
sudo ip netns exec client curl -6 -s -o /dev/null -w "IPv6 time_total: %{time_total}s\n" http://[fd00::2]/
```
Both succeed, both fast. This is the fully-healthy baseline.

## Step 3 — Break only the IPv6 service port
```bash
sudo ip netns exec server ip6tables -A INPUT -p tcp --dport 80 -j DROP
```
Note exactly what this does and doesn't touch: it drops TCP port 80
specifically. Nothing about IPv6 reachability itself, or ICMPv6, is
affected.

## Step 4 — Diagnose: ping6 lies to you here, on purpose
```bash
sudo ip netns exec client ping6 -c 2 fd00::2
```
This **succeeds**. IPv6 is fully reachable at the network layer — the
server's IPv6 address is up, routable, answering. If you stopped here,
you'd conclude IPv6 is fine.
```bash
sudo ip netns exec client curl -6 --max-time 5 -s -o /dev/null -w "IPv6 time_total: %{time_total}s\n" http://[fd00::2]/
```
This **hangs for the full 5 seconds and fails**. The service port itself
is a black hole — no RST, no ICMP unreachable, just silence, so the client
has no way to fail fast; it can only wait out its own timeout.
> Gotcha: `ping6` tests network-layer reachability. `curl -6` (or anything
> that actually opens the TCP port you care about) tests the thing you
> actually need working. A passing ping and a broken service are not a
> contradiction — they're testing two different layers.

## Step 5 — See what a client with no fallback logic does
```bash
sudo ip netns exec client timeout 5 bash -c 'exec 3<>/dev/tcp/fd00::2/80' && echo "connected" || echo "TIMED OUT after 5s"
```
A client that only tries the address it's handed — no race, no fallback —
just hangs for the full connect timeout. This is what "IPv6 half-broken"
looks like to any client that isn't specifically Happy-Eyeballs-aware:
not an error, a **wait**.

## Step 6 — See what a Happy-Eyeballs-aware client does with the same break
```bash
sudo ip netns exec client curl --max-time 5 -s -o /dev/null \
  -w "dual-stack (v6 blackholed) time_total: %{time_total}s\n" \
  --resolve svc.test:80:10.0.0.2,fd00::2 http://svc.test/

sudo ip netns exec client curl --max-time 5 -s -o /dev/null \
  -w "IPv4-only (as if v6 didn't exist) time_total: %{time_total}s\n" \
  --resolve svc.test:80:10.0.0.2 http://svc.test/
```
`--resolve host:port:addr1,addr2` hands curl both addresses for the same
name, the same way DNS returning both an A and AAAA record would — curl
races them per RFC 8305 instead of trying one, waiting, then trying the
other. Compare the two `time_total` values: the dual-stack run costs a
small but real penalty (curl's head-start delay before it also tries
IPv4) over the IPv4-only run, even though curl handled the failure about
as gracefully as possible. **That penalty exists on every single
connection, forever, for as long as IPv6 stays half-broken** — a fully
*absent* AAAA record would have cost exactly nothing.

## Step 7 — Fix it
```bash
sudo ip netns exec server ip6tables -D INPUT -p tcp --dport 80 -j DROP
```
Re-run Step 6 — both `curl` calls should now land at roughly the same
`time_total`, because there's no longer a broken attempt for Happy
Eyeballs to race against.

## Challenges

**Challenge A:**
```bash
sudo ip netns exec server ip6tables -A INPUT -p icmpv6 --icmpv6-type neighbor-solicitation -j DROP
sudo ip netns exec server ip6tables -A INPUT -p icmpv6 --icmpv6-type neighbor-advertisement -j DROP
```
This time, run both diagnostics from Step 4 again:
```bash
sudo ip netns exec client ping6 -c 2 fd00::2
sudo ip netns exec client curl -6 --max-time 5 -s -o /dev/null -w "%{time_total}s\n" http://[fd00::2]/
```
Both fail now, not just the curl one. Explain, in terms of what actually
has to happen before an IPv6 packet can be put on the wire at all, why
this is a *different* layer of failure than Step 3's, even though the
`ip6tables` command that caused it looks superficially similar.

**Challenge B:**
```bash
sudo ip netns exec server ip6tables -A INPUT -p tcp --dport 80 -j DROP
sudo ip netns exec client curl --max-time 10 -s -o /dev/null \
  -w "long happy-eyeballs timeout: %{time_total}s\n" \
  --happy-eyeballs-timeout-ms 5000 \
  --resolve svc.test:80:10.0.0.2,fd00::2 http://svc.test/
```
The IPv6 port is blackholed exactly like Step 3, and this `curl` fully
supports Happy Eyeballs — yet the result looks much closer to Step 5's
naive, no-fallback client than to Step 6's well-behaved one. What single
number is responsible, and what does it tell you about Happy Eyeballs as a
mitigation — is supporting RFC 8305 enough on its own, or does something
else have to be true too?

See `solution.md` only after you've formed your own diagnosis.
