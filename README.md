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
30. DBRE combo labs (replication lag, connection pool exhaustion, network partition)

## Prerequisites
- A Linux VM (tested on \[fill in your distro/version\])
- `iproute2`, `unshare`/`nsenter` (util-linux), root/sudo access
- Later labs: Docker, containerlab, FRR
