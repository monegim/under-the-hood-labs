# Context for continuing this project

## What this is
Repo: `under-the-hood-labs` (already pushed to GitHub by the user).
Purpose: hands-on Linux/networking/DBRE labs, published on GitHub and
presented on YouTube. Audience: viewers who want real troubleshooting
skill, not toy tutorials.

## Format (every lab must follow this)
- `labs/NN-topic-name/README.md`:
  - Objective (1-2 lines)
  - Why it matters (ties to real tools: Docker/K8s/containerlab/MySQL)
  - Prerequisites
  - Step-by-step build (numbered, copy-pasteable commands)
  - 2 "break it" challenges at the end — NO answers given here
- `labs/NN-topic-name/SOLUTION.md`:
  - Written like a postmortem: what to check, what you'd find, the fix,
    the lesson. Not just "run this command."
- `setup.sh` (optional): script to build the "before" state automatically

## Teaching style (important — user explicitly wants this)
- Walk through BUILDING the lab, not just handing over a finished fix
- After each exploratory step, ask the user what they observed BEFORE
  explaining — the observing is part of the skill being built
- Simple, plain English. No "newspaper language" / no unnecessary jargon
- Ask clarifying questions before big decisions, don't just barrel ahead
- User prefers being consulted with options, not decisions made for them

## Roadmap (30 labs, 3 tracks) — ALL 30 WRITTEN

Every lab below has README.md + SOLUTION.md; labs 20-30 also have a
`setup.sh`; labs 10-19 also have a `topology.clab.yml`; lab 30 also has a
`docker-compose.yml`.

### Track 1 — Linux internals (build a container from scratch)
1. Network namespaces
2. PID + mount namespaces
3. cgroups
4. Put it together: your own container (chroot + namespaces + cgroups)
5. Overlay filesystems
6. Kubernetes internals
7. eBPF basics

### Track 2 — Networking (containerlab + FRR)
8. Linux bridge
9. VLANs
10. Static routing
11. NAT
12. Firewalls
13. OSPF
14. BGP
15. GRE tunnels
16. VXLAN
17. IPsec
18. MTU issues
19. Packet captures

### Track 3 — Production troubleshooting (Linux + DBRE combined)
20. Why is the server slow
21. Process stuck in D state
22. OOM killer takes out MySQL
23. Disk 20% full but writes fail
24. Service won't start after reboot
25. Log partition full
26. Deleted-but-open file eating disk
27. High CPU steal time
28. Too many open files
29. Permissions vs ACLs
30. DBRE combo labs (replication lag, connection pool exhaustion, network
    partition)

## Environment
User runs labs in a Linux VM on a Mac M2 Pro. Has `iproute2`, `unshare`,
`nsenter` available. Networking labs (10-19) need Docker + containerlab +
the FRR container image; troubleshooting labs (20-30) need MySQL/MariaDB
via apt, and lab 30 needs docker-compose.

## Where things stand
All 30 labs were drafted in one batch (5 parallel writers, one per track
slice) on 2026-08-02, following the format above and modeled on
sadservers.com (realistic broken-box scenarios) and labs.iximiuz.com
(build-the-real-mechanism-from-scratch teaching style), per explicit user
request to stop the step-by-step interactive teaching flow and just
generate everything.

**None of this has been run end-to-end on a live VM.** Every lab was
written from careful reasoning about real tool behavior (kernel/cgroup
semantics, `ip`/iptables/nft syntax, FRR `vtysh` config, systemd/journald
behavior, MySQL replication), not from an actual test run. Each writer
flagged specific low-confidence spots in their own report — before
recording, a dry run of each lab is warranted, with extra attention to:
- Lab 6 (`kind` version pin, kube-proxy default mode)
- Lab 7 (bpftrace `args.field` vs `args->field` syntax depends on version)
- Labs 10-19 (containerlab `frr` kind image tag, `/etc/frr/daemons`
  enable-daemon mechanism for OSPF/BGP)
- Lab 21 (loopback-NFS D-state reproduction — kernel/rpcbind-version
  dependent)
- Lab 22 (cgroup-v2 OOM timing — memory limit may need tuning per VM)
- Lab 30 (MySQL primary/replica docker-compose + I/O-contention setup)

## Next steps
1. Spin up the actual Linux VM and dry-run each lab's numbered steps +
   both challenges, fixing anything that doesn't match reality.
2. Decide recording order (probably track 1 → track 3 → track 2, or
   whatever matches the roadmap, since track 2 has the heaviest
   infra/tooling prerequisites).
3. Commit and push once verified (nothing has been committed yet —
   everything so far is uncommitted working-tree changes).