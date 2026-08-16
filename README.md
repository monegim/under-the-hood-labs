# Under the Hood — SRE/DBRE Troubleshooting Labs

[![Lint](https://github.com/monegim/under-the-hood-labs/actions/workflows/lint.yml/badge.svg)](https://github.com/monegim/under-the-hood-labs/actions/workflows/lint.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Labs](https://img.shields.io/badge/labs-104%2F~120-blue)

Most "hands-on Linux/networking/DBRE" content teaches you how to configure
things. This teaches you how to **troubleshoot** them — build the system,
break it on purpose, diagnose it with the same tools you'd use in a real
incident, then read a postmortem that explains not just the fix but *why*
it happened and why the obvious fix often doesn't work.

If you like [sadservers.com](https://sadservers.com) (realistic broken
boxes you diagnose from scratch) or
[labs.iximiuz.com](https://labs.iximiuz.com) (build the real mechanism
yourself instead of memorizing commands), this is built in that spirit —
free, offline, and run entirely on your own VM. No sandboxed browser
terminal, no subscription: clone it, build it, break it, fix it.

Structured like a game: six levels, increasing in scope and difficulty,
roughly 120 labs total once complete.

## Each lab contains

- `README.md` — objective, why it matters, step-by-step build (numbered,
  copy-pasteable), then 2 "break it" challenges — **no answers given here**
- `solution.md` — the diagnosis process and fix, written like a postmortem:
  root cause, why it happened, why common fixes don't work, the commands
  that reveal it, how to prevent it, real-world examples
- `CONCEPTS.md` — the mechanism explained properly (not just "run this
  command"), plus 3-6 curated resources (books, docs, YouTube channels) to
  go deeper
- `setup.sh` — builds the "before" broken state automatically
- `check.sh` — automatically verifies whether you actually fixed it
- `reset.sh` — restores the broken state so you can retry

## Levels

### Level 1 — Linux Basics (25 built / 21 planned) ✅
Not "how to use `ps`" — how Linux actually works under a real incident.
Split into two halves: **foundations** (build the underlying mechanism
yourself — namespaces, cgroups, overlayfs, a container from scratch,
eBPF) and **troubleshooting** (a simulated production incident per lab,
including strace/ltrace, boot failures, zombie processes, clock drift,
shell-toolkit labs on awk/sed log forensics and xargs/history bulk
operations, and tmux session persistence). [`labs/linux/`](labs/linux)

Tools: `ps`, `top`/`htop`, `vmstat`, `iostat`, `strace`, `lsof`, `journalctl`, `/proc`, `systemctl`, `tmux`

### Level 2 — Networking (25 built / 25 planned) ✅
Every SRE should be comfortable debugging packets. [`labs/networking/`](labs/networking)

Tools: `tcpdump`, `ip`, `ss`, `bridge`, `conntrack`, `iptables`/`nftables`, `dig`, `mtr`, `tracepath`

### Level 3 — Storage (12 built / 15 planned)
LVM full/snapshot full, XFS/btrfs corruption, ext4 recovery, RAID
degraded, slow disks, disk quotas, ZFS pool degraded, Docker storage
driver bloat, a simulated failing drive, filesystems the kernel flips
read-only on its own. Everything built on disposable loop devices —
nothing touches a real disk. [`labs/storage/`](labs/storage)

### Level 4 — Databases (17 built / 20 planned)
Exactly what a DBRE sees. MySQL (replication lag, GTID conflicts,
deadlocks, slow queries, metadata locks, disk full, binlog corruption,
connection storms, InnoDB redo log full, semi-sync timeout, partition
pruning failure, ProxySQL misrouting — 12/12) and PostgreSQL (replication
lag, WAL full, autovacuum, index bloat, lock contention — 5/5).
[`labs/mysql/`](labs/mysql) · [`labs/postgres/`](labs/postgres)

### Level 5 — Kubernetes (17 built / 20 planned)
Pod networking, CoreDNS failure, etcd full, expired certs, stuck PVCs,
node pressure, CNI failure, broken ingress, API server unavailable,
kubelet cert rotation, HPA not scaling, resource quotas, admission
webhooks, StatefulSet PVC mismatch, PDB blocking drain, RBAC
misconfiguration, probe misconfiguration, taints/tolerations — all on a
`kind` cluster. [`labs/kubernetes/`](labs/kubernetes)

### Level 6 — Production Incidents (8 built / 20 planned)
Combines two or more mechanisms from Levels 1-5 into a single synthetic
incident: a realistic on-call page, symptoms only, no hint which
subsystem is at fault. [`labs/incidents/`](labs/incidents)

## Status

**104 of ~120 labs are written.** Levels 1 (Linux Basics, 25/21) and 2
(Networking, 25/25) are past/at their original target counts. Level 3
(Storage) is at 12/15, Level 4 (Databases) is complete for its current
scope — MySQL (12/12) and Postgres (5/5) — Level 5 (Kubernetes) is at
17/20, and Level 6 (Incidents) is at 8/20.

Every lab across every level has full `check.sh`/`reset.sh` automation.
Most labs also have `setup.sh`; the containerlab-based networking labs
(03 onward) instead build the "before" state live via the README's own
steps, matching that sub-format's existing convention.

**None of this has been run end-to-end on a live VM yet** — every command
was written from careful reasoning about real tool behavior (a few labs
were partially verified locally where practical — e.g. the awk/sed log
forensics lab's core pipelines, the tmux session-persistence mechanism —
but not the full labs end to end). Treat it as a first draft to dry-run
before recording, not verified fact. See [`CONTEXT.md`](CONTEXT.md) for
the full list of what's flagged as needing a live check — a few items
are flagged as genuinely low-confidence (exact `dm-flakey` argument
syntax, `kind`+etcd quota behavior, a couple of timing-sensitive
PostgreSQL challenges) and worth prioritizing in a dry run.

Remaining to reach ~120: Level 3 (3 more Storage topics), Level 4 (3
more across both databases), Level 5 (3 more Kubernetes topics), Level 6
(12 more incidents). Levels 1 and 2 are done for now — their original
target counts (21 and 25) have been met.

## Contributing

This is a solo project with a lot of open labs left to build (see
"Remaining to reach ~120" above) — contributions welcome. See
[`CONTRIBUTING.md`](CONTRIBUTING.md) for the exact format every lab
needs to follow before opening a PR.

## Prerequisites
- A Linux VM (tested on \[fill in your distro/version\])
- `iproute2`, `unshare`/`nsenter` (util-linux), root/sudo access, `tmux`
- Level 2 (Networking): Docker + [containerlab](https://containerlab.dev) + FRR
- Level 3 (Storage): `lvm2`, `xfsprogs`, `e2fsprogs`, `mdadm`, `sysstat`, `fio`, `smartmontools`, `dmsetup`, `zfsutils-linux`, `btrfs-progs`
- Level 4 (Databases): MySQL/MariaDB or Docker + docker-compose, depending on the lab
- Level 5 (Kubernetes): Docker + [`kind`](https://kind.sigs.k8s.io/) + `kubectl`
- Level 6 (Incidents): Docker + docker-compose, containerlab for one incident
