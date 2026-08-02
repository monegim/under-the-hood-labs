# Lab 12 — Concept: Netfilter, Chains, and Why Order and Policy Are Separate State

## What's actually going on

`iptables` is a userspace tool for configuring **netfilter**, a set of
hook points built directly into the Linux kernel's networking stack. As a
packet moves through the stack, it passes specific hook locations —
`PREROUTING`, `INPUT`, `FORWARD`, `OUTPUT`, `POSTROUTING` — and at each one
the kernel walks an ordered list of rules (a "chain") attached to that
hook, evaluating them top-to-bottom, first match wins. `FORWARD` is the
hook for packets being routed *through* the box to somewhere else;
`INPUT` is the hook for packets destined for the box itself (a process
listening on that host). These are genuinely separate decision points with
separate rule lists and separate default policies — which is exactly why
Step 6 locking down `INPUT` had zero effect on `FORWARD` traffic, and vice
versa. A router doing pure forwarding for other hosts can be wide open on
`FORWARD` while being completely locked down on `INPUT`, or the reverse.

A chain has two independent pieces of state: its ordered rule list, and
its **default policy** — what happens if a packet falls off the end
without matching any rule. `iptables -F` (flush) only clears the rule
list; it does not touch the policy. This is the exact mechanism behind
Challenge A: after Step 3 set `FORWARD`'s policy to `DROP`, flushing every
rule doesn't reset you to some neutral "not configured" state — it resets
you to an empty chain that falls straight through to a DROP policy,
meaning literally everything now gets dropped. The kernel doesn't have a
concept of "originally there were no rules and no explicit policy either";
every chain always has *some* policy, and the built-in chains default to
`ACCEPT` until you change it.

Rule position matters because chain traversal is strictly ordered and
stops at the first match. `-A` appends to the end of the chain; `-I chain
N` inserts at position N, shoving everything currently at N and after down
by one. This is why Challenge B's `iptables -I FORWARD 1 -p tcp --sport 80
-j DROP` broke an established connection that Step 5's stateful rule was
supposed to protect: putting the new DROP rule at position 1 means it is
now evaluated *before* the `ESTABLISHED,RELATED` ACCEPT rule ever gets a
chance to run, for any packet matching `--sport 80`. The server's replies
(SYN-ACK, ACK, data) all have source port 80, so they die at the new rule
before reaching the rule that would have waved them through as return
traffic for a connection the firewall itself allowed outbound. ICMP is
untouched because the match is TCP-specific — a different protocol simply
never triggers that rule at all.

The `-m state --state ESTABLISHED,RELATED` rule from Step 5 depends on
**conntrack**, the kernel's connection-tracking subsystem, which keeps a
table of every flow (5-tuple: protocol, src/dst IP, src/dst port) and its
current state (NEW, ESTABLISHED, RELATED, INVALID). This is what lets one
rule cover return traffic for *any* connection already permitted outbound,
instead of needing a hand-mirrored ACCEPT rule per direction per service —
conntrack, not the rule itself, is doing the work of recognizing "this
packet belongs to a flow I already approved."

## Where this shows up in the real world

Every cloud security group, NSG (Azure), and NACL is an abstraction over
exactly this model: an ordered (or, for security groups, typically
stateful-and-unordered-but-still-allow-list) set of rules plus an implicit
default-deny. The two failure modes in this lab are the two most common
real firewall incidents: someone "clears the rules for a quick test"
during a maintenance window and doesn't realize the policy underneath is
still deny-everything (Challenge A), and someone inserts an urgent DROP
rule "just for this one bad source" at the top of the chain and
accidentally breaks return traffic for connections nobody meant to touch
(Challenge B). Reading `iptables -L -v -n --line-numbers` and checking
both the policy line and rule order — not just "is there a rule that
should allow this" — is what turns a five-minute fix into a five-minute
fix instead of an hour of guessing.

## Go deeper

- **Book:** *Network Warrior* — Gary A. Donahue — practical coverage of stateful firewalling concepts that map directly onto iptables/netfilter chain design.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man8/iptables.8.html — the canonical reference for chain traversal order, policies, and the `-m state`/conntrack match.
- **Website/blog:** Julia Evans' blog — https://jvns.ca — has concrete, plain-English posts on iptables/netfilter debugging; search for "iptables."
- **YouTube:** NetworkChuck — https://www.youtube.com/@NetworkChuck — accessible walkthroughs of firewall/iptables fundamentals.
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal — practical iptables and network security demos.
