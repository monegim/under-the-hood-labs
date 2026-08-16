# Lab 28 — Concept: Two Firewalls, One Host

## What's actually going on

Linux implements IPv4 and IPv6 packet filtering as two entirely
separate netfilter table sets, configured through two entirely separate
userspace tools — `iptables` for IPv4, `ip6tables` for IPv6 — each with
its own independent chains, rules, and policies. This isn't a historical
accident that got fixed later; it reflects that IPv4 and IPv6 are
genuinely different protocols at the packet level (different header
formats, different addressing, different fragmentation rules), so the
kernel's packet-filtering hooks for each stack are naturally distinct
codepaths. The practical consequence is that `iptables -A INPUT ...`
has exactly zero effect on IPv6 traffic, no matter how it's written, and
vice versa — there was never a shared configuration layer to
accidentally rely on; the separation has always been complete.

A "dual-stack" host or service — one that's reachable over both IPv4
and IPv6 — is therefore protected by the *intersection* of what both
rule sets actually enforce, not by whichever one you happen to think of
as "the firewall." If only one rule set restricts a given port, the
service is exactly as reachable as if no rule existed at all, over
whichever protocol was never addressed — there's no fallback or
default-deny that kicks in for the stack nobody configured; the
default, absent any rules, is to accept everything, on both stacks
independently.

`net.ipv6.conf.*.disable_ipv6` operates at an entirely different layer
than either firewall — it's a kernel networking-stack toggle that
removes IPv6 addressing and processing from an interface (or globally)
altogether, well below where iptables/ip6tables ever get a chance to
evaluate anything. It can make a specific "is this port reachable over
v6" test pass, but it does so by removing IPv6 connectivity entirely,
not by making a scoped decision about the one port in question — which
is precisely why it's the wrong tool for what looks, from the test
alone, like the same job.

## Where this shows up in the real world

As IPv6 adoption has grown (many cloud providers and modern networks
enable it by default now), "we blocked this port" audits that only test
over IPv4 — because that's what the runbook says, that's what the
monitoring checks, that's the address everyone types first — are a
real, documented class of security gap. It's specifically insidious
because everything *looks* correct: the firewall rule exists, it's
correctly written, it's actively blocking traffic — just only for half
of the traffic that could reach the service. Security scanners and
compliance audits that don't explicitly test both address families can
miss this category of misconfiguration entirely, reporting a host as
"the port is filtered" based on an IPv4-only check.

## Go deeper

- **Website/docs:** `ip6tables(8)` man page — https://man7.org/linux/man-pages/man8/ip6tables.8.html — full reference for IPv6 netfilter rule syntax, largely parallel to `iptables(8)` but a genuinely separate tool.
- **Website/docs:** nftables official wiki — https://wiki.nftables.org/ — the netfilter successor project, including its unified, address-family-agnostic rule model that structurally avoids this exact class of drift.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man7/ipv6.7.html — the `ipv6(7)` man page, covering the IPv6 stack fundamentals including `disable_ipv6` and related sysctls.
- **Book:** *Linux Firewalls* — Michael Rash (No Starch Press) — covers dual-stack firewall configuration as part of its broader iptables treatment.
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal — has IPv6 fundamentals content alongside broader networking/security material.
