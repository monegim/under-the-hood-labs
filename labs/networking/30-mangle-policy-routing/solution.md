# Lab 30 — Solution

## Root cause

`router`'s `mangle PREROUTING` chain correctly marks `client`'s
traffic bound for port 9000 with `MARK 0x64` — this is real, verified
work the packet actually goes through, which is exactly what makes it
misleading to stop investigating there. Marking a packet changes
nothing about how it gets routed, on its own. Routing decisions are
made by consulting `ip rule` (an ordered list of policy rules, each
pointing at a routing table) and then the routing table that rule
selects. With no `ip rule` referencing `fwmark 0x64` at all, every
marked packet is routed exactly the same as an unmarked one: via
`main`, which has no route to `target`'s subnet, so the packet dies
there — silently, since there's no firewall drop involved, just an
absence of any usable route.

## Why it happened

`iptables -t mangle` and `ip rule`/`ip route ... table N` are entirely
separate subsystems with no automatic link between them — setting a
mark is a complete, self-contained action from `iptables`' point of
view, and it has no way of knowing (or caring) whether anything
downstream ever acts on that mark. Most walkthroughs of policy routing
lead with the `MARK` step because it's the more novel-looking half;
the `ip rule` step can read as an afterthought, or get skipped
entirely by someone who copies the mangle rule from a working example
without realizing a second, independent piece of configuration is
required to make it do anything.

## Why the obvious fixes don't work

- **Re-adding/tweaking the mangle rule**: does nothing - the rule
  already fires correctly, confirmed by its own packet counter. The
  mark was never the missing piece.
- **Adding a route for `target`'s subnet directly to the main table**:
  "fixes" connectivity, but defeats the entire point - now *all*
  traffic to that subnet takes the special path unconditionally,
  whether it's marked or not, which is a completely different (and
  usually wrong) outcome than "only this specific traffic class should
  use this path."
- **Restarting anything**: neither `iptables` rules nor `ip rule`/`ip
  route` configuration are tied to any process that a restart would
  affect - the missing policy rule is missing until someone explicitly
  adds it, indefinitely.

## The investigation

Confirm the symptom:
```bash
sudo ip netns exec client bash -c 'echo hi | nc -w3 10.30.0.2 9000'
```
Times out, no response.

Confirm the mark is actually being applied - this is the step that's
easy to treat as sufficient on its own:
```bash
sudo ip netns exec router iptables -t mangle -L PREROUTING -n -v
```
Non-zero, climbing packet counter.

Check what's actually consulting that mark:
```bash
sudo ip netns exec router ip rule show
```
Only `local`/`main`/`default` - nothing referencing `fwmark 0x64` at
all.

Confirm the route that *should* be used already exists, just not
anywhere reachable yet:
```bash
sudo ip netns exec router ip route show table 100
```

## The fix

```bash
sudo ip netns exec router ip rule add fwmark 0x64 table 100 priority 100
```
Traffic matching the mark is now looked up in table 100 first, finds
the route to `target` via `gwb`, and succeeds - with zero changes to
the mangle rule that was already correct.

## Challenge A — the rule is there, and it still doesn't work

**Check:**
```bash
sudo ip netns exec router ip rule add fwmark 0x64 table 100 priority 40000
sudo ip netns exec router ip rule show
```
```
0:	from all lookup local
32766:	from all lookup main
32767:	from all lookup default
40000:	from all fwmark 0x64 lookup 100
```

**Diagnosis:** `ip rule` entries are evaluated in ascending priority
order - the *lowest* number goes first, exactly like `iptables` chains
are walked top to bottom, and the first matching rule that resolves a
route wins. `main` (priority `32766`) sits *before* this rule
(`40000`), so every packet - marked or not - gets its route resolved
by `main` first, which has no route to `target`'s subnet and fails,
before evaluation ever reaches priority `40000`. The rule isn't broken
or ignored; it's just never consulted, because something earlier in
the ordered list already produced an answer (a failed one) first.

**Fix:** use a priority number lower than `main`'s `32766` - anything
that places the rule earlier in the list:
```bash
sudo ip netns exec router ip rule del fwmark 0x64 table 100 priority 40000
sudo ip netns exec router ip rule add fwmark 0x64 table 100 priority 100
```

**Lesson:** a policy rule that "exists" in `ip rule show` proves
nothing about whether it's actually reachable - exactly the same
lesson as an unreachable `iptables` rule buried after a catch-all, just
one layer over, in `ip rule`'s own ordering instead of a chain's.

---

## Challenge B — right priority, right mark, still nothing

**Check:**
```bash
sudo ip netns exec router ip rule add fwmark 0x64 table 200 priority 100
sudo ip netns exec router ip route show table 200
```
```
Error: ipv4: FIB table does not exist.
```

**Diagnosis:** the rule's priority is correct this time - it's
evaluated before `main`, and it does match the mark. But it points at
table `200`, and the actual route was added to table `100` (Step 4/5
of the main lab). Table `200` has never had anything added to it, so
the lookup finds nothing there and - critically - policy routing
doesn't stop and fail outright at an empty table; it falls through to
the *next* rule in the list, which is `main`, which also has no route
to `target`. The end result is identical to every other failure in
this lab: a timeout with nothing else to go on.

**Fix:** match the rule's table number to wherever the route actually
lives:
```bash
sudo ip netns exec router ip rule del fwmark 0x64 table 200 priority 100
sudo ip netns exec router ip rule add fwmark 0x64 table 100 priority 100
```

**Lesson:** `ip rule show` and `ip route show table N` are two
separate pieces of state that both have to agree with each other -
`ip rule` alone will never tell you whether the table it references
actually contains anything, and a table number typo (or a route added
to the wrong table by habit/copy-paste) produces the exact same silent
symptom as no rule existing at all. When policy routing "isn't
working," check the rule *and* the specific table it points at as two
separate, equally necessary facts, not one combined assumption.
