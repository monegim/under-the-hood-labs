# Lab 26 — Concept: How iptables Actually Evaluates a Chain

## What's actually going on

An `iptables` chain is not a set of rules the kernel considers together
and picks the "best" match from — it's a strictly ordered list, walked
top to bottom, where the **first** rule that matches a packet decides
its fate immediately (for a terminating target like `ACCEPT`/`DROP`/
`REJECT`) and evaluation of that chain stops right there. This is why
rule *position*, not just rule *content*, determines behavior — two
rulesets containing the exact same rules in a different order can
produce completely different outcomes.

A jump to a custom chain (`-j CHAINNAME`) is itself just another rule
with a match condition — when it matches, evaluation continues inside
the named chain, walked the same top-to-bottom way. Critically, if a
packet reaches the end of a custom chain without matching any rule
inside it, evaluation doesn't stop or default to any particular verdict
— it **returns** to the calling chain, resuming right after the jump
rule, and continues evaluating from there. A custom chain with no
explicit terminating rule of its own is therefore not "deny by default"
or "allow by default" — it's neither, and whatever happens next depends
entirely on what rule follows the jump in the chain that called it.
This return-on-no-match behavior is the single most common source of
"my custom chain isn't working" confusion — the chain isn't broken, it
genuinely has nothing to say about packets it didn't match, and
authority passes back to whoever called it.

`-A` (append) and `-I` (insert) differ only in *where* the new rule
lands, and `iptables` never reasons about that for you — appending
always adds at the end of the chain's current rule list, no matter what
already terminates it earlier. This is exactly why a specific allow rule
appended after an existing catch-all deny is permanently unreachable:
the deny rule already claims every matching packet before the new one
is ever consulted. `iptables -L --line-numbers` exists specifically to
make chain position visible and countable, so you can target an
`-I CHAIN <N>` insert at exactly the right spot relative to what's
already there.

## Where this shows up in the real world

Rule-order mistakes are one of the most common classes of firewall
misconfiguration precisely because a ruleset can look completely correct
read rule-by-rule and still be broken by their relative order — code
review of a firewall change that only checks "is this rule correct in
isolation" misses this class of bug entirely; you have to trace the
whole chain's evaluation order. It's also a very common
migration/refactor bug: someone reorganizes rules into a cleaner-looking
custom chain for maintainability, and the reorganization itself
silently changes which rules are actually reachable, without changing
any individual rule's content at all.

## Go deeper

- **Website/docs:** Netfilter/iptables official documentation — https://www.netfilter.org/documentation/ — the canonical, authoritative source for chain traversal, jump/return semantics, and target behavior.
- **Website/docs:** `iptables(8)` man page — https://man7.org/linux/man-pages/man8/iptables.8.html — full reference for `-A`/`-I`/`-N`/`-L` and every match/target option.
- **Book:** *Linux Firewalls* — Michael Rash (No Starch Press) — a full practical treatment of iptables rule design, including custom chains and rule ordering discipline.
- **Website/docs:** DigitalOcean's iptables tutorials — a widely-used, clearly-written practical series on iptables rule structure and chain design (search "DigitalOcean iptables essentials" — not linking a specific article URL to avoid citing one that may have moved).
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal — has firewall/iptables-focused networking content alongside broader networking material.
