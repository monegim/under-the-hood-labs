# Under the Hood — SRE/DBRE Troubleshooting Labs

[![Lint](https://github.com/monegim/under-the-hood-labs/actions/workflows/lint.yml/badge.svg)](https://github.com/monegim/under-the-hood-labs/actions/workflows/lint.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Labs](https://img.shields.io/badge/labs-122%2F~120-blue)

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

### Level 2 — Networking (29 built / 25 planned) ✅
Every SRE should be comfortable debugging packets — including a
dedicated set of `iptables` mechanics labs (rule order/custom chains,
rules lost on reboot, the IPv4-only-firewall/IPv6-wide-open gap, and
rate limiting done right). [`labs/networking/`](labs/networking)

Tools: `tcpdump`, `ip`, `ss`, `bridge`, `conntrack`, `iptables`/`nftables`, `dig`, `mtr`, `tracepath`

### Level 3 — Storage (15 built / 15 planned) ✅
LVM full/snapshot full, XFS/btrfs corruption, ext4 recovery, RAID
degraded, slow disks, disk quotas, ZFS pool degraded, Docker storage
driver bloat, a simulated failing drive, filesystems the kernel flips
read-only on its own, NFS stale mounts, swap exhaustion, I/O scheduler
misconfiguration. Everything built on disposable loop devices — nothing
touches a real disk. [`labs/storage/`](labs/storage)

### Level 4 — Databases (26 built / 20 planned) ✅
Exactly what a DBRE sees. MySQL (replication lag, GTID conflicts,
deadlocks, slow queries, metadata locks, disk full, binlog corruption,
connection storms, InnoDB redo log full, semi-sync timeout, partition
pruning failure, ProxySQL misrouting, purge lag/History List Length,
manual primary promotion, ProxySQL connection-pool exhaustion,
auto-increment exhaustion, point-in-time recovery, InnoDB corruption
recovery — 18/12, grown well past its original target for deeper MySQL
DBRE coverage) and
PostgreSQL (replication lag, WAL full, autovacuum, index bloat, lock
contention, connection pooler exhaustion, transaction ID wraparound,
logical replication conflicts — 8/8). [`labs/mysql/`](labs/mysql) ·
[`labs/postgres/`](labs/postgres)

### Level 5 — Kubernetes (19 built / 20 planned)
Pod networking, CoreDNS failure, etcd full, expired certs, stuck PVCs,
node pressure, CNI failure, broken ingress, API server unavailable,
kubelet cert rotation, HPA not scaling, resource quotas, admission
webhooks, StatefulSet PVC mismatch, PDB blocking drain, RBAC
misconfiguration, probe misconfiguration, taints/tolerations, image pull
failures — all on a `kind` cluster. [`labs/kubernetes/`](labs/kubernetes)

### Level 6 — Production Incidents (8 built / 20 planned)
Combines two or more mechanisms from Levels 1-5 into a single synthetic
incident: a realistic on-call page, symptoms only, no hint which
subsystem is at fault. [`labs/incidents/`](labs/incidents)

## Status

**122 of ~120 labs are written.** Levels 1 (Linux Basics, 25/21), 2
(Networking, 29/25), 3 (Storage, 15/15), and 4 (Databases, 26/20) are
past their target counts — MySQL (18/12, deliberately grown well past
target for deeper DBRE coverage) and Postgres (8/8). Level 5 (Kubernetes)
is at 19/20, and Level 6 (Incidents) is at 8/20.

Every lab across every level has full `check.sh`/`reset.sh` automation.
Most labs also have `setup.sh`; the containerlab-based networking labs
(03 onward) instead build the "before" state live via the README's own
steps, matching that sub-format's existing convention.

**Most of this has not been run end-to-end on a live VM yet** — commands
were written from careful reasoning about real tool behavior (a few labs
were partially verified locally where practical — e.g. the awk/sed log
forensics lab's core pipelines, the tmux session-persistence mechanism —
but not the full labs end to end). Treat it as a first draft to dry-run
before recording, not verified fact. The three newest PostgreSQL labs
(`06-connection-pooler-exhaustion`, `07-transaction-id-wraparound-emergency`,
`08-logical-replication-conflict`) are the exception — every command in
all three was actually run against live Docker containers while writing
them, which caught and fixed several real bugs a read-through wouldn't
have (a `psql -c` multi-statement string silently wrapping `COMMIT`
inside a procedure in an implicit transaction, `docker exec` dropping a
heredoc's stdin without `-i`, `autovacuum_freeze_max_age` rejecting
values below Postgres's actual hard minimum, and `ALTER SYSTEM` losing
to a command-line-pinned GUC). The two newest Kubernetes labs
(`15-rbac-misconfiguration`, `19-image-pull-failure`) got the same
treatment against live `kind` clusters — swapped a slow-pulling
`bitnami/kubectl` image for a `curl`-plus-mounted-token approach after
watching it repeatedly stall, and confirmed live that a `RoleBinding`
accepts a dangling `roleRef` silently, that a `ClusterRole`'s reach is
capped by whether it's bound via `RoleBinding` vs. `ClusterRoleBinding`
(not by which role type it references, which was the original, wrong
assumption), and that `kind load docker-image` is genuinely required —
a plain `docker build` on the host is invisible to a `kind` node's own
containerd. The three newest MySQL labs
(`13-history-list-length-purge-lag`, `14-primary-failure-manual-promotion`,
`15-proxysql-connection-pool-exhaustion`) got the same live-Docker
treatment — caught a missing `DELIMITER` wrapper that broke a stored
procedure, confirmed that InnoDB purge is held back by the single
*oldest* open transaction specifically (killing a newer, more
"obvious"-looking blocker first does nothing, verified with a 90-second
pinned-value test), reproduced a genuine `AUTO_INCREMENT` primary-key
collision from promoting the wrong replica, and confirmed live that
ProxySQL enforces three independent, differently-failing connection
ceilings rather than one. Two more labs
(`16-auto-increment-exhaustion`, `17-point-in-time-recovery`) got the
same treatment, and along the way a real, already-shipped bug got fixed
in `12-proxysql-routing-failure`: its admin-interface commands only
worked from inside the ProxySQL container itself (`-h proxysql` from
another container fails — ProxySQL's admin user is local-only by
default), a `BEGIN`/`COMMIT`-wrapped reproduction step that ProxySQL's
own transaction-pinning silently defeated, and a documented
`mysql_replication_hostgroups` "auto re-break" claim that didn't
reproduce under repeated live testing and was replaced with a verified
query-cache-staleness scenario instead. One more
(`18-innodb-corruption-recovery`) followed the same discipline after an
earlier attempt at this exact topic was abandoned for being
unreproducible — this time a gentler, checksum-only fault (not the
destructive one that kept crashing `mysqld` unrecoverably before) made
the whole recovery flow work cleanly, and live testing also surfaced
that `innodb_force_recovery`'s highest level doesn't crash on genuinely
corrupted row data — it can return a wrong answer that looks completely
successful, which became the lab's sharpest lesson. See [`CONTEXT.md`](CONTEXT.md) for the
full list of what's flagged as needing a live check — a few items are
flagged as genuinely low-confidence (exact `dm-flakey` argument syntax,
`kind`+etcd quota behavior, a couple of timing-sensitive PostgreSQL
challenges in the original five Postgres labs) and worth prioritizing in
a dry run.

Remaining to reach ~120: Level 5 (1 more Kubernetes topic), Level 6 (12
more incidents). Levels 1, 2, 3, and 4 are done for now — their original
target counts (21, 25, 15, and 20) have been met — Level 2 grew further
still to add a dedicated `iptables` mechanics set, and Level 4 grew
further to deepen MySQL DBRE coverage specifically.

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
