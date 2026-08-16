# Lab 27 — Concept: Why iptables Rules Don't Survive a Reboot on Their Own

## What's actually going on

`iptables` (and the underlying `netfilter` framework it configures) is
purely a kernel runtime mechanism — every `-A`/`-I`/`-D`/`-F` command
manipulates in-memory tables the kernel is currently using to filter
packets, right now, in this boot session. None of that has any
persistence layer built in; the kernel doesn't write netfilter rules to
disk, checkpoint them, or remember them across a restart, because
that's simply not part of what the kernel's netfilter subsystem is
responsible for. Every fresh boot starts with default, empty
built-in-chain tables (policy `ACCEPT`, no rules) — exactly as if
nothing had ever been configured, because from the kernel's perspective,
nothing has been, yet, this boot.

Getting rules to survive a reboot requires two entirely separate,
independently-necessary pieces working together: something that
serializes the current ruleset to a file (`iptables-save`, which just
prints the current tables in a restorable text format), and something
that runs during boot, before anything starts depending on the firewall
being correctly configured, that reads that file back in
(`iptables-restore`, invoked automatically by a boot-time service).
On Debian/Ubuntu, that service is provided by the
`iptables-persistent`/`netfilter-persistent` package, which installs a
systemd unit hardcoded to read from specific paths
(`/etc/iptables/rules.v4`, `/etc/iptables/rules.v6`) and only runs at
boot if that unit is **enabled** — installing the package alone gets you
the tooling and the correct file paths, but a systemd service that
exists and is enabled are two different states, exactly like any other
systemd unit.

This is why the failure mode in this lab has three genuinely
independent points of failure, not one: the rule can be missing from
the live tables (nobody applied it, or a flush happened), the saved
file can be missing or in the wrong location (nobody ran `save`, or
redirected `iptables-save`'s output somewhere the loader doesn't read
from), or the loading service can be installed but not enabled. All
three have to be correct simultaneously for a rule to genuinely survive
a real reboot — and none of them are visible from `iptables -L` alone,
which only ever shows you the live, in-memory state.

## Where this shows up in the real world

"We blocked that port/IP after an incident, and it was open again after
a routine kernel-update reboot" is a real, recurring class of
self-inflicted security incident, precisely because `iptables -L`
showing the rule *before* the reboot gives false confidence that it's
"handled" — nothing about applying a rule live tells you anything about
whether it will still be there tomorrow. Teams that manage firewall
rules by hand rather than through configuration management (which
typically reapplies desired state on every run, sidestepping this
entire class of bug) are the most exposed to exactly this gap.

## Go deeper

- **Website/docs:** Debian wiki — iptables — https://wiki.debian.org/iptables — covers `iptables-persistent`/`netfilter-persistent` setup and the exact file paths/service behavior on Debian-based systems.
- **Website/docs:** `iptables-save(8)`/`iptables-restore(8)` man pages — https://man7.org/linux/man-pages/man8/iptables-save.8.html — authoritative reference for the save/restore file format and behavior.
- **Website/docs:** `systemd.service(5)` man page — https://man7.org/linux/man-pages/man5/systemd.service.5.html — for the general "installed vs enabled vs active" service model this lab's persistence gap depends on understanding.
- **Book:** *Linux Firewalls* — Michael Rash (No Starch Press) — covers persistent firewall configuration as part of a broader practical iptables treatment.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — has systemd service and firewall persistence content alongside its broader Linux administration material.
