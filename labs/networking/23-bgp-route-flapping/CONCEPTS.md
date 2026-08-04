# Lab 23 — Concept: BGP Route Flapping & Dampening

## What's actually going on

Every time a BGP session drops and re-establishes, it isn't just a
transport-layer event — it forces a full re-run of BGP's route
advertisement logic on both sides. When the session drops, the routes
learned over it are withdrawn (an explicit UPDATE with a withdrawal, or
implicitly once the session times out); when it re-establishes, those
routes get re-advertised from scratch. This is why Step 5's link flapping
shows up on r3 at all — r3 doesn't peer with r1, and doesn't know or care
that a physical link went down two hops away, but it absolutely receives
and processes the withdrawal and re-advertisement UPDATEs that r2 relays
as a direct consequence of that link's instability. Route flapping is
this effect at scale: an unstable source keeps generating fresh
UPDATEs, and every router in the propagation path keeps re-running best-
path selection and reprogramming its FIB in response, for a route whose
actual "final" state hasn't meaningfully changed — it's just thrashing.

BGP route dampening is a penalty-based mechanism built directly into this
problem: track a numeric penalty per prefix per peer, add a fixed amount
every time that prefix flaps, and let the penalty decay exponentially with
a configured half-life. Once a prefix's penalty crosses the
*suppress-threshold*, the local router stops advertising it downstream
entirely, even on cycles where it's technically back up — this is what
Step 9 demonstrates as a single early `ABSENT` on r3 that then *holds*,
rather than continuing to toggle in sync with r1's link. The prefix stays
suppressed until its decaying penalty drops back below the lower
*reuse-threshold*, at which point it's allowed to be re-advertised, capped
by a hard *max-suppress-time* ceiling regardless of how the math works out.
This is the exact algorithm from RFC 2439, and it's why dampening
parameters come in that specific four-number group
(half-life / reuse / suppress / max-suppress-time) rather than a single
on/off switch — each number tunes a different part of "how sensitive" and
"how long."

The tradeoff this lab is built to make concrete is structural, not a
tuning mistake: dampening cannot tell the difference between "still
unstable" and "stable again" except by waiting and watching the penalty
decay. A route that becomes genuinely, permanently healthy the instant
after it crosses the suppress threshold still has to sit out the same
decay curve as one that's still flapping, because from the local router's
point of view those two situations are indistinguishable at the moment
suppression kicks in. Challenge B pushes this further: with production-
realistic timers (a 15-minute half-life is a common real-world default),
a single legitimate blip — not sustained instability at all — can still
cross the suppress threshold and then sit suppressed for a genuinely long
time, because the parameters were tuned for tolerating sustained
instability over that timescale, not for distinguishing single events from
repeated ones. This is precisely why `clear bgp dampening` exists as a
manual override: an operator who has independently confirmed a route is
healthy again shouldn't be forced to wait out an algorithm that has no way
to know that on its own.

## Where this shows up in the real world

- Flapping fiber/optics (a transceiver on the edge of its power budget, a
  half-seated SFP, a submarine cable segment with intermittent faults) are
  classic real-world causes of exactly this pattern — an ISP's edge router
  sees a peering session bounce every few minutes, and without dampening,
  every downstream router in that ISP's network (and potentially routers
  in *other* ASes learning the same prefix transitively) re-converges
  every single time, at internet scale.
- Dampening is deliberately controversial in real deployments: several
  major ISPs have historically disabled it entirely or tuned it very
  conservatively, precisely because of Challenge B's effect at a much
  larger scale — a single legitimate maintenance-related flap on a
  well-connected prefix, over-dampened, can make that prefix effectively
  unreachable from large parts of the internet for longer than the
  maintenance window itself.
- **Diagnosis scenario:** a downstream service that depends on a specific
  route becomes unreachable, recovers, and the upstream network team
  insists "the link has been fine for 20 minutes" — `show bgp dampening
  dampened-paths` (or the Cisco-equivalent) on the router closest to you
  is the fast way to confirm whether you're looking at an active problem
  or a still-decaying penalty from a problem that's already over.

## Go deeper
- **Website/docs:** FRRouting docs — https://docs.frrouting.org — official reference for the exact `bgp dampening` command syntax, `show bgp dampening dampened-paths`, and `clear bgp dampening` used in this lab.
- **Website/docs:** ipSpace.net — https://ipspace.net — Ivan Pepelnjak has written extensively on BGP route dampening's real-world tradeoffs and why several large networks disable or heavily tune it.
- **Book:** *Network Warrior* — Gary A. Donahue — covers BGP session stability and flap-related troubleshooting from a practical operations perspective.
- **Website/docs:** NetworkLessons.com — https://networklessons.com — structured tutorials on BGP dampening's penalty/half-life/suppress/reuse mechanics that map directly onto this lab's parameters.
