# Linux, Networking & DBRE — Hands-On Labs

A series of hands-on labs to build real SRE/DBRE troubleshooting skill —
not just "what is a VLAN," but build it, break it, and diagnose it yourself
using the same tools you'd use in a real incident.

Each lab follows the same format:
- `README.md` — objective, why it matters, step-by-step build, then challenges (no answers)
- `SOLUTION.md` — the diagnosis process and fix, written like a postmortem
- `setup.sh` — optional script to build the "before" state automatically

## Roadmap

### Track 1 — Linux internals (build a container from scratch)
1. [Network namespaces](labs/01-network-namespaces)
2. [PID + mount namespaces](labs/02-pid-mount-namespaces)
3. [cgroups](labs/03-cgroups)
4. [Put it together: your own container](labs/04-build-your-own-container) (chroot + namespaces + cgroups)
5. [Overlay filesystems](labs/05-overlay-filesystems)
6. [Kubernetes internals](labs/06-kubernetes-internals)
7. [eBPF basics](labs/07-ebpf-basics)

### Track 2 — Networking (containerlab + FRR)
8. [Linux bridge](labs/08-linux-bridge)
9. [VLANs](labs/09-vlans)
10. [Static routing](labs/10-static-routing)
11. [NAT](labs/11-nat)
12. [Firewalls](labs/12-firewalls)
13. [OSPF](labs/13-ospf)
14. [BGP](labs/14-bgp)
15. [GRE tunnels](labs/15-gre-tunnels)
16. [VXLAN](labs/16-vxlan)
17. [IPsec](labs/17-ipsec)
18. [MTU issues](labs/18-mtu-issues)
19. [Packet captures](labs/19-packet-captures)

### Track 3 — Production troubleshooting (Linux + DBRE combined)
20. [Why is the server slow](labs/20-why-is-the-server-slow)
21. [Process stuck in D state](labs/21-process-stuck-in-d-state)
22. [OOM killer takes out MySQL](labs/22-oom-killer-mysql)
23. [Disk 20% full but writes fail](labs/23-disk-full-writes-fail)
24. [Service won't start after reboot](labs/24-service-wont-start-after-reboot)
25. [Log partition full](labs/25-log-partition-full)
26. [Deleted-but-open file eating disk](labs/26-deleted-open-file-eating-disk)
27. [High CPU steal time](labs/27-high-cpu-steal-time)
28. [Too many open files](labs/28-too-many-open-files)
29. [Permissions vs ACLs](labs/29-permissions-vs-acls)
30. [DBRE combo labs](labs/30-dbre-combo-labs) (replication lag, connection pool exhaustion, network partition)

All 30 labs are written. Labs 10-19 use [containerlab](https://containerlab.dev) +
FRR topologies; labs 20-30 ship a `setup.sh` that reproduces the "before"
incident state; lab 30 ships a `docker-compose.yml` for a MySQL
primary/replica pair. None of this has been run end-to-end on a live VM yet —
treat it as a first draft to dry-run before recording, not verified fact.

## Prerequisites
- A Linux VM (tested on \[fill in your distro/version\])
- `iproute2`, `unshare`/`nsenter` (util-linux), root/sudo access
- Later labs: Docker, containerlab, FRR
