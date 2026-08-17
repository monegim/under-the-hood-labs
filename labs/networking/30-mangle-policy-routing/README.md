# Lab 30 — Mangle Table Policy Routing

## Objective
Mark a specific class of traffic with `iptables`' `mangle` table so it
takes a dedicated path instead of the default route, watch the mark
fire exactly as intended, and still fail — because marking a packet
and routing it based on that mark are two separate steps, and only one
of them is actually configured.

## Why this matters
The `mangle` table's most common real use isn't blocking or allowing
traffic at all — `filter` already does that — it's altering how a
packet gets *routed*: setting a `MARK` that a later, completely
separate subsystem (`ip rule` / policy routing) can act on. That split
is exactly where this breaks in practice: `iptables -t mangle` and
`ip rule`/`ip route add ... table N` are two independent tools with no
built-in awareness of each other. A `mangle` rule that fires correctly
— visible right there in its own packet counters — proves nothing about
whether policy routing is actually using that mark for anything. Most
guides show the `MARK` half of this and assume the `ip rule` half is
obvious; in practice it's the step that gets forgotten, or gets added
with a typo'd table number or the wrong priority, and the failure mode
looks identical either way from the outside: traffic that should take
a specific path just... doesn't, with no error anywhere explaining why.

## Prerequisites
- A Linux VM, `sudo` access, `iptables`, `iproute2`, `netcat-openbsd`

Check first:
```bash
which iptables ip nc
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This builds five namespaces: `client`, `router` (the box doing the
policy routing), `gwa` (the default/main path, doesn't lead anywhere
useful), `gwb` (the only path that actually reaches `target`), and
`target`, running a small service on port 9000. `router`'s main
routing table has **no route to `target`'s subnet at all** — only a
separate table (`100`) does. `router` marks `client`'s traffic bound
for port 9000 in `mangle PREROUTING` — correctly.

## Step 2 — Reproduce the symptom
```bash
sudo ip netns exec client bash -c 'echo hi | nc -w3 10.30.0.2 9000'
```
Times out. No response, no error explaining why.

## Step 3 — Confirm the mark is actually firing
```bash
sudo ip netns exec router iptables -t mangle -L PREROUTING -n -v
```
The rule's packet counter is non-zero and climbing every time you
retry Step 2. The mark is being applied. This is the trap: it's easy
to stop here, see the counter incrementing, and conclude "the mangle
rule works, so this must be something else."

## Step 4 — Check whether anything is actually using that mark
```bash
sudo ip netns exec router ip rule show
```
There's no rule referencing the mark at all — just `local`, `main`,
and `default`. `router`'s main table (`main`) has no route to
`target`'s subnet, so every marked packet still falls through to it
and dies there. The route that *would* work already exists:
```bash
sudo ip netns exec router ip route show table 100
```

## Step 5 — Fix it
```bash
sudo ip netns exec router ip rule add fwmark 0x64 table 100 priority 100
```

## Step 6 — Verify
```bash
./check.sh
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the rule is there, and it still doesn't work:**
```bash
./reset.sh
sudo ip netns exec router ip rule add fwmark 0x64 table 100 priority 40000
sudo ip netns exec router ip rule show
sudo ip netns exec client bash -c 'echo hi | nc -w3 10.30.0.2 9000'
```
The rule referencing the mark and the correct table is right there in
`ip rule show` — and the connection still times out. Compare the
priority number on this rule against `main`'s. `ip rule` entries are
evaluated in a specific numeric order — which direction, and what does
that mean for a rule numbered *higher* than `main`?

**Challenge B — right priority, right mark, still nothing:**
```bash
./reset.sh
sudo ip netns exec router ip rule add fwmark 0x64 table 200 priority 100
sudo ip netns exec router ip rule show
sudo ip netns exec router ip route show table 200
sudo ip netns exec client bash -c 'echo hi | nc -w3 10.30.0.2 9000'
```
This time the priority is correct — it sits *before* `main`. Still
fails. Check what's actually inside the table this rule points at,
compared to the table the real route lives in (Step 4). What's the
practical difference between "the mark isn't being consulted at all"
(Step 3/4's failure) and "the mark is being consulted, but points
somewhere empty" (this one) — and how would you tell them apart
quickly, under pressure, without already knowing the answer?

See `solution.md` only after you've formed your own diagnosis.
