# Lab 23 — Solutions

## Challenge A — session Established, route still withheld

**Check:**
```bash
docker exec clab-bgp-flap-lab-r2 vtysh -c "show bgp summary"
docker exec clab-bgp-flap-lab-r2 vtysh -c "show bgp ipv4 unicast"
docker exec clab-bgp-flap-lab-r2 vtysh -c "show bgp dampening dampened-paths"
```
`show bgp summary` shows the r1 neighbor `Established` throughout — the
transport session is completely healthy. `show bgp ipv4 unicast` marks
`1.1.1.1/32` with a dampening status flag (history/damped), and
`show bgp dampening dampened-paths` lists it explicitly with its current
penalty and reuse time.

**Diagnosis:** dampening operates at the *prefix* level, entirely inside
BGP's route-selection logic — it never touches the underlying TCP session
or the BGP FSM. A dampened route's session is, correctly, still
Established, because nothing about the session is actually the problem.
This is functionally the same category of mistake as Lab 7's Challenge B
(checking session state and stopping there), but here it's even easier to
get wrong, because unlike Lab 7 the route genuinely *was* being advertised
correctly earlier — it's being deliberately, temporarily withheld due to
its own recent history, which `show bgp summary` was never designed to
reveal.

**Fix:** nothing to fix here — this is expected behavior. To see the real
state, use `show bgp dampening dampened-paths` or `show bgp <prefix>` (the
per-prefix detail includes the dampening penalty and flap history), not
the neighbor/session-level command.

**Lesson:** every BGP troubleshooting lesson in this series comes back to
the same idea from a new angle: "the session is up" answers exactly one
question. Route advertisement (Lab 7), route dampening (this lab), and
plenty of other route-selection logic all sit on top of a healthy session
and can each independently withhold a route your session status will never
show you.

---

## Challenge B — aggressive real-world dampening values over-penalize a single blip

**Check:**
```bash
docker exec clab-bgp-flap-lab-r2 vtysh -c "show bgp dampening dampened-paths"
```
One single down/up cycle is enough to suppress `1.1.1.1/32`, and the
listed reuse time reflects the 15-minute half-life / 60-minute
max-suppress-time now configured — meaningfully longer than the actual
disruption (one link blip lasting a few seconds).

**Diagnosis:** this is not a malfunction — it's exactly what these
parameters tell dampening to do, and it's the central tradeoff of route
dampening as a mechanism. Production-realistic half-lives are long (15
minutes is a common default) specifically to protect against sustained,
repeated instability over that kind of timescale. The unavoidable side
effect is that dampening can't distinguish "a link that flaps every 30
seconds for an hour" from "a link that went down once for routine
maintenance and came right back" until *after* the fact — a single flap
adds the same initial penalty either way, and the parameters decide how
long it takes to forgive.

**Fix — three legitimate options, not mutually exclusive:**
```bash
# Option 1: tune parameters to your actual environment (shorter half-life
# and/or higher suppress threshold so single blips don't cross it)
docker exec clab-bgp-flap-lab-r2 vtysh \
  -c "configure terminal" \
  -c "router bgp 65002" \
  -c "address-family ipv4 unicast" \
  -c "no bgp dampening 15 750 2000 60" \
  -c "bgp dampening 2 1500 3000 10" \
  -c "exit-address-family" \
  -c "end"

# Option 2: manually clear the current suppression once you've confirmed
# the route is actually fine, rather than waiting out the timer
docker exec clab-bgp-flap-lab-r2 vtysh -c "clear bgp dampening"
```

**Lesson:** dampening parameters are a real operational tuning decision,
not a set-and-forget default — too aggressive and legitimate single events
(a planned reboot, a one-time cable reseat) get punished with outages
longer than the event itself; too lax and it stops doing its job against
genuinely flapping links. `clear bgp dampening` (or the per-prefix form,
`clear bgp dampening <prefix>`) exists precisely because operators need a
way to override the timer once they've manually confirmed a suppressed
route is trustworthy again, rather than being stuck waiting.
