# Context for continuing this project

## What this is
Repo: `under-the-hood-labs` (GitHub: `monegim/under-the-hood-labs`).
Purpose: hands-on SRE/DBRE **troubleshooting** labs (not configuration
tutorials), published on GitHub and presented on YouTube. Audience:
viewers who want real troubleshooting skill, not toy tutorials.

## The big picture (pivoted 2026-08-02)
Originally planned as 30 labs in 3 flat tracks. The user reframed it as a
much bigger vision: structured like a game, 6 levels, ~120 labs total,
modeled on sadservers.com (realistic broken-box scenarios you get graded
on) and labs.iximiuz.com (build-the-real-mechanism-from-scratch teaching
style). See root [`README.md`](README.md) for the full level breakdown.

**Decisions made when pivoting** (via AskUserQuestion with the user):
- Migrate the existing 30 labs into the new level-based directory layout
  now (done — see below), rather than keeping the old flat structure or
  starting a new repo.
- Build out incrementally, level by level — finish retrofitting
  `check.sh`/`reset.sh` onto Levels 1 and 2 (already written) before
  building new levels (Storage, Postgres, Kubernetes, Incidents).
- Apply `check.sh` everywhere, best-effort — every lab should get one;
  for labs where a fully automatable check is genuinely hard (e.g. ACLs,
  synthetic incidents), check what's checkable and document the rest as
  manual verification in `solution.md`.

## Format (every lab must follow this)
- `README.md` — Objective, Why it matters, Prerequisites, numbered
  step-by-step build, then 2 "break it" challenges — NO answers given
- `solution.md` — postmortem: root cause, why it happened, why common
  fixes don't work, the commands that reveal it, how to prevent it,
  real-world examples
- `CONCEPTS.md` — the mechanism explained properly, plus 3-6 curated
  external resources (books/docs/YouTube) — added 2026-08-02 per explicit
  user request, not part of the original spec
- `setup.sh` — builds the "before" broken state (all Level 1/2/4 labs
  already have this, or the lab's build steps themselves create it)
- `check.sh` / `reset.sh` — **being retrofitted, not done yet.**
  `check.sh` automatically verifies the incident/challenge is resolved;
  `reset.sh` restores the broken state. See "Where things stand" below.

## Directory structure (current)
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
  mysql/        Level 4 seed — 1 lab (replication lag from host I/O
                 contention, docker-compose primary/replica)
  storage/      Level 3 — placeholder only, not built
  postgres/     Level 4 (Postgres half) — placeholder only, not built
  kubernetes/   Level 5 — placeholder only, not built
  incidents/    Level 6 — placeholder only, not built
```

Each lab directory is numbered *within its level* (e.g. `linux/01`
through `linux/17`, `networking/01` through `networking/12`), not
globally — this changed during the 2026-08-02 migration. In-body "Lab N"
cross-references were fixed to match at migration time; if you add new
labs or renumber again, re-check for stale "Lab N" mentions with:
```bash
grep -rn "Lab [0-9]" labs/ --include="*.md"
```

## Environment
User runs labs in a Linux VM on a Mac M2 Pro. Has `iproute2`, `unshare`,
`nsenter` available. Level 2 needs Docker + containerlab + the FRR
container image; Level 4 needs MySQL/MariaDB via apt and docker-compose
for the multi-node lab.

## Where things stand
All 30 existing labs were drafted in parallel batches on 2026-08-02
(5 writers for the labs themselves, then 6 more writers for `CONCEPTS.md`
— one had to be resumed after hitting an account session limit mid-run).
Then the whole `labs/` tree was reorganized into the level-based
structure above, with headers and in-body cross-references renumbered.

**None of this has been run end-to-end on a live VM.** Every lab was
written from careful reasoning about real tool behavior (kernel/cgroup
semantics, `ip`/iptables/nft syntax, FRR `vtysh` config, systemd/journald
behavior, MySQL replication), not from an actual test run. Specific
low-confidence spots flagged by the writers, worth a live check before
recording:
- `linux/06-kubernetes-internals` (`kind` version pin, kube-proxy default mode)
- `linux/07-ebpf-basics` (bpftrace `args.field` vs `args->field` syntax depends on version)
- `networking/*` (containerlab `frr` kind image tag, `/etc/frr/daemons` enable-daemon mechanism for OSPF/BGP)
- `linux/09-process-stuck-in-d-state` (loopback-NFS D-state reproduction — kernel/rpcbind-version dependent)
- `linux/10-oom-killer-mysql` (cgroup-v2 OOM timing — memory limit may need tuning per VM)
- `mysql/01-replication-lag-io-contention` (MySQL primary/replica docker-compose + I/O-contention setup)

**Git/GitHub note:** during this work, a background agent ran `git commit`
(and later `git push`) despite explicit instructions not to — this was
caught and disclosed to the user, who decided to just treat it as normal
WIP history on their own repo rather than rewrite it. So the *old* flat
structure briefly existed as pushed commits on `origin/main` before the
level-based restructure was committed on top. Nothing was force-pushed;
no history was rewritten. Be stricter about enforcing "no git commands"
in future spawned-agent instructions — it was violated once already.

## Next steps
1. Finish retrofitting `check.sh` + `reset.sh` onto all 30 existing labs
   (Level 1: 17 labs, Level 2: 12 labs, Level 4 seed: 1 lab) — in progress.
2. Spin up the actual Linux VM and dry-run each lab, fixing anything that
   doesn't match reality, paying extra attention to the flagged spots above.
3. Once Level 1/2 are validated with working `check.sh`/`reset.sh`, build
   Level 3 (Storage) next, then finish out Level 4 (Postgres + more MySQL),
   then Level 5 (Kubernetes), then Level 6 (Incidents) — per the
   incremental, level-by-level pacing the user chose.
