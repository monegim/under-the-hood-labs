# Lab 26 — Solutions

## Challenge A — a jump that "falls through" instead of deciding

**Check:**
```bash
sudo ip netns exec ns2 iptables -L INPUT -n -v --line-numbers
```
`INPUT`'s last rule is a bare `ACCEPT` — and traffic that doesn't match
`ALLOWED`'s allow-list still gets through, landing on that final
`ACCEPT`.

**Diagnosis:** jumping to a custom chain (`-j ALLOWED`) is not the same
as "evaluate this chain, and whatever it decides is final." If a packet
enters a custom chain and matches none of that chain's rules, control
**returns** to the calling chain and continues evaluating from the rule
*after* the jump — the custom chain didn't reject anything, it just had
nothing to say, and evaluation carries on. Here, that means: no match in
`ALLOWED` → fall back into `INPUT` → hit the final bare `ACCEPT` →
allowed anyway. The custom chain looks like a gate; without an explicit
terminating decision at its end, it's actually just a filter that
*sometimes* accepts and otherwise does nothing.

**Fix:** give the custom chain an explicit default at its end, or make
sure the calling chain's next rule after the jump is a `DROP`, not an
`ACCEPT`:
```bash
sudo ip netns exec ns2 iptables -A ALLOWED -j DROP
```
Now anything that reaches `ALLOWED` and doesn't match its explicit
allow-list is dropped inside the chain, instead of falling back out to
whatever the caller does next.

**Lesson:** a jump to a custom chain is a *maybe* (accept if matched,
otherwise return and keep going), never an implicit *always decide
here*. If you want a custom chain to behave like a firewall gate rather
than an optional filter, it needs its own explicit terminating rule —
don't assume "it didn't match, so it must have been rejected."

---

## Challenge B — appended after the point of no return

**Check:**
```bash
sudo ip netns exec ns2 iptables -L INPUT -n -v --line-numbers
```
The specific `ACCEPT` rule sits at line 3 — *after* the catch-all
`DROP` at line 2.

**Diagnosis:** `iptables -A` (**a**ppend) always adds the new rule at
the *end* of the chain, regardless of what's already there — it never
reasons about where the rule "should" go relative to existing entries.
Appending a specific allow rule after a catch-all `DROP` guarantees it
can never be reached: the `DROP` already terminated evaluation for
every matching packet before the new rule is ever considered.

**Fix:** use `-I` (**i**nsert) with an explicit position instead,
placing the new rule *before* the `DROP`:
```bash
sudo ip netns exec ns2 iptables -D INPUT -p tcp --dport 8080 -s 10.10.0.1 -j ACCEPT
sudo ip netns exec ns2 iptables -I INPUT 2 -p tcp --dport 8080 -s 10.10.0.1 -j ACCEPT
```
(`-I INPUT 2` inserts at position 2, ahead of the `DROP` that's
currently there.)

**Lesson:** `-A` and `-I` are not interchangeable conveniences —
`-A` is correct only when you genuinely want the new rule evaluated
last (or when the chain currently has no terminating catch-all yet);
the moment a chain already has a catch-all `DROP`/`REJECT`/`ACCEPT`,
every new specific rule needs `-I` with a position *before* it, or it's
dead on arrival. Always `iptables -L --line-numbers` first to know
exactly where you're inserting relative to.
