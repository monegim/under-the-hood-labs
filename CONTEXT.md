# Context for continuing this project

## What this is
Repo: `under-the-hood-labs` (GitHub: `monegim/under-the-hood-labs`).
Purpose: hands-on SRE/DBRE **troubleshooting** labs (not configuration
tutorials), published on GitHub and presented on YouTube. Audience:
viewers who want real troubleshooting skill, not toy tutorials.

## The big picture (pivoted 2026-08-02, all 6 levels seeded 2026-08-03)
Originally planned as 30 labs in 3 flat tracks. The user reframed it as a
much bigger vision: structured like a game, 6 levels, ~120 labs total,
modeled on sadservers.com (realistic broken-box scenarios you get graded
on) and labs.iximiuz.com (build-the-real-mechanism-from-scratch teaching
style). See root [`README.md`](README.md) for the full level breakdown
and current build counts.

**Decisions made when pivoting** (via AskUserQuestion with the user):
- Migrate the existing 30 labs into the new level-based directory layout
  (done). Build out incrementally, level by level. Apply `check.sh`
  everywhere, best-effort.
- After Level 1/2 were fully retrofitted with `check.sh`/`reset.sh`, the
  user said to move on to the planned levels ("go to the planned parts —
  storage, incidents...") — read as "build out all 5 remaining levels,"
  not just those two by name.

## Format (every lab must follow this)
- `README.md` — Objective, Why it matters, Prerequisites, numbered
  step-by-step build, then 2 "break it" challenges — NO answers given
  (Level 6 incidents use a different shape: The page / Environment /
  Your task / Getting unstuck, since there's no guided build — see
  `labs/incidents/README.md` for the exact format)
- `solution.md` — postmortem: root cause, why it happened, why common
  fixes don't work, the commands that reveal it, how to prevent it,
  real-world examples
- `CONCEPTS.md` — the mechanism explained properly, plus 3-6 curated
  external resources (books/docs/YouTube) — added 2026-08-02 per explicit
  user request, not part of the original spec
- `setup.sh` — builds the "before" broken state
- `check.sh` — verifies the incident/challenge is currently resolved
- `reset.sh` — restores the broken state so you can retry

**All of the above is now true for every one of the 63 labs currently in
the repo** — the check.sh/reset.sh retrofit and the full build-out of
Levels 3-6 are both complete as of 2026-08-03.

## Directory structure (current) — 63 labs total
```
labs/
  linux/        Level 1 — 17 labs (01-07 foundations: build-it-yourself
                 namespaces/cgroups/container/overlayfs/k8s-internals/eBPF;
                 08-17 troubleshooting: slow server, D-state, OOM+MySQL,
                 disk/inode full, service-won't-start, log-partition-full,
                 deleted-open-file, CPU steal time, too-many-open-files,
                 permissions-vs-ACLs)
  networking/   Level 2 — 12 labs (bridge, VLANs, static routing, NAT,
                 firewalls, OSPF, BGP, GRE, VXLAN, IPsec, MTU, packet
                 captures) — containerlab + FRR
  storage/      Level 3 — 7 labs (LVM full, XFS corruption, ext4 recovery,
                 RAID degraded, slow disks, simulated NVMe failure,
                 filesystem read-only) — loop devices + device-mapper,
                 nothing touches a real disk. Inode exhaustion intentionally
                 NOT duplicated here — already covered by linux/11.
  mysql/        Level 4 (MySQL half) — 8 labs (replication lag, GTID
                 conflicts, deadlocks, slow queries, metadata locks, disk
                 full, binlog corruption, connection storms)
  postgres/     Level 4 (Postgres half) — 5 labs (replication lag, WAL
                 full, autovacuum disabled, index bloat, lock contention)
  kubernetes/   Level 5 — 9 labs, all on `kind` (pod networking, CoreDNS,
                 etcd full, cert expired, PVC stuck, node pressure, CNI
                 failure, ingress broken, API server unavailable)
  incidents/    Level 6 — 5 labs, combining 2+ mechanisms from other
                 levels into a single synthetic on-call incident (see the
                 different README format note above)
```

Each lab directory is numbered *within its level*, not globally. In-body
"Lab N" cross-references were fixed to match at the 2026-08-02 migration.
If you add new labs or renumber again, re-check for stale "Lab N"
mentions with:
```bash
grep -rn "Lab [0-9]" labs/ --include="*.md"
```

## Environment
User runs labs in a Linux VM on a Mac M2 Pro. Has `iproute2`, `unshare`,
`nsenter` available. Level 2 needs Docker + containerlab + FRR. Level 3
needs `lvm2`/`xfsprogs`/`e2fsprogs`/`mdadm`/`sysstat`/`fio`/
`smartmontools`/`dmsetup`. Level 4 needs MySQL/MariaDB or Docker +
docker-compose depending on the lab. Level 5 needs Docker + `kind` +
`kubectl`. Level 6 needs Docker + docker-compose (+ containerlab for one).

## Where things stand
All 63 labs (30 original + 33 built 2026-08-03 across Storage, Postgres,
Kubernetes, the MySQL remainder, and Incidents) were drafted by parallel
background agents, each given: a complete reference lab to read first
(usually `labs/linux/11-disk-full-writes-fail`), a strict format spec,
and a pre-vetted resource pool for `CONCEPTS.md` to prevent fabricated
book/site/YouTube citations.

**None of this has been run end-to-end on a live VM.** Every lab was
written from careful reasoning about real tool behavior, not from an
actual test run (one agent — Kubernetes — did verify some specifics via
live web search rather than pure recall: the kind+Calico NetworkPolicy
setup, the etcd quota/compact/defrag sequence, kind+ingress-nginx setup).
Specific low-confidence spots flagged by the writers, worth a live check
before recording, roughly ordered by how worried to be:

- `storage/06-nvme-failure` Challenge B — the `dm-flakey` `corrupt_bio_byte` table syntax was written from memory, not verified against `Documentation/admin-guide/device-mapper/dm-flakey.rst`. **Highest priority to verify.**
- `kubernetes/03-etcd-full` — lowering etcd's `--quota-backend-bytes` can crash-loop etcd's own static pod container instead of cleanly hitting NOSPACE; a `crictl`-based fallback is documented but untested live.
- `postgres/01-replication-lag` Challenge B and `postgres/04-index-bloat` Challenge B — both are timing-sensitive races (a recovery-conflict needing the primary's VACUUM to hit rows the standby's snapshot needs; killing Postgres mid-`REINDEX CONCURRENTLY` on a fast/small table) — may need a retry in practice, noted in the lab text.
- `mysql/07-binlog-corruption` — rests on the assumption that MySQL 8.0's crash-recovery scan only validates the actively-open binlog file at restart, not older rotated ones. Believed correct per documented behavior, not exercised live.
- `mysql/06-disk-full` Challenge B — the row-count/iteration math to overflow a 100M tmp partition via filesort is an estimate, not measured.
- `linux/03-cgroups` `check.sh` — uses `python3` to trigger an OOM kill inside a throwaway cgroup, but `python3` isn't in that lab's stated prerequisites (only `stress-ng` is). Either confirm `python3` is present or swap the check to use `stress-ng --vm`.
- `linux/04-build-your-own-container` and `linux/05-overlay-filesystems` — their `check.sh`/`reset.sh` originally used `$HOME` for paths, which breaks under `sudo` (resets to `/root`); this was caught and fixed with a `SUDO_USER`/`getent passwd` resolution during the same agent run, but the fix itself hasn't been tested live.
- `linux/06-kubernetes-internals` (`kind` version pin, kube-proxy default mode), `linux/07-ebpf-basics` (bpftrace `args.field` vs `args->field` syntax version-dependent), `networking/*` (containerlab `frr` image tag, `/etc/frr/daemons` enable-daemon mechanism), `linux/09-process-stuck-in-d-state` (loopback-NFS D-state reproduction, kernel/rpcbind-version dependent), `linux/10-oom-killer-mysql` (cgroup-v2 OOM timing may need per-VM tuning), `mysql/01-replication-lag-io-contention` (docker-compose + I/O-contention setup) — carried over from the original 30-lab batch, still unverified.

**Git/GitHub note:** during the original 30-lab batch, a background agent
ran `git commit` (and later `git push`) despite explicit instructions not
to — this was caught and disclosed to the user, who decided to just treat
it as normal WIP history on their own repo rather than rewrite it. Since
then, every agent prompt has carried an "ABSOLUTE RULE: DO NOT RUN ANY
GIT COMMANDS, not even `git status`" instruction, and all git operations
(commit/push) have been done directly by the orchestrating session
instead of delegated to agents. No further violations have occurred.

## Next steps
1. Spin up the actual Linux VM (or a `kind`/Docker-capable box for the
   later levels) and dry-run each lab, starting with the highest-priority
   flagged items above, fixing anything that doesn't match reality.
2. Decide recording order.
3. Once dry-run-validated, keep expanding each level toward its full
   target count (see the "Remaining to reach ~120" note in the root
   README) — 3 more Linux Basics, 13 more networking, 7 more databases,
   11 more Kubernetes, 15 more incidents. Storage's target was revised
   down from 15 to effectively 7 (inode exhaustion intentionally
   deduplicated against Level 1) unless more storage topics come up.
