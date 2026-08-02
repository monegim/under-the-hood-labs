# Lab 1 — Concept: Network Namespaces

## What's actually going on

A network namespace isn't a virtual machine and it isn't a container — it's a
kernel data structure, `struct net`, that bundles together everything the
networking stack needs per-instance: the interface list, routing tables,
iptables/nftables rule sets, `/proc/net` contents, socket lookup tables, the
lot. Every process on a normal Linux box is already "in" a network namespace —
it's just that until you create more than one, every process shares the same
one (the initial `struct net`, sometimes called `init_net`). `ip netns add
ns1` doesn't do anything mysterious: it calls `unshare(CLONE_NEWNET)`-style
logic in the kernel to allocate a fresh `struct net`, and by convention `ip
netns` also bind-mounts a file under `/var/run/netns/ns1` so the namespace has
a name and stays alive even with zero processes in it (network namespaces are
reference-counted; without that bind mount, an empty one would be freed
immediately).

When you did `ip netns exec ns1 <cmd>`, under the hood that's calling
`setns(fd, CLONE_NEWNET)` on the process before exec'ing — `setns()` is the
syscall that lets an existing process jump into a namespace that already
exists, as opposed to `clone(CLONE_NEWNET)` / `unshare(CLONE_NEWNET)` which
create a brand new one. This is exactly the same syscall `docker exec` and
`kubectl exec` use to attach a shell to a running container's network: they
resolve the container's namespace to a file descriptor (via `/proc/<pid>/ns/net`)
and `setns()` into it.

The veth pair is the other half of the mechanism. A veth pair is genuinely
two ends of one virtual wire at the driver level — packets written to one
end's TX ring show up on the other end's RX ring, full stop, no switching
logic involved. Each end is a normal `struct net_device` like any NIC, which
means each end can independently live in a different network namespace
(`ip link set veth1 netns ns1`) — that's the entire trick behind connecting
two namespaces: create the pair while both ends are still in the root
namespace, then move each end into a different one. Nothing routes between
them unless you add a bridge, veth-to-veth is inherently point-to-point.

The `/proc/<pid>/ns/net` symlink you inspected in Step 5 is the namespace's
identity as far as userspace tooling is concerned — it's not a real file,
it's a magic symlink whose target encodes the namespace's inode number
(`net:[4026531840]` style). Two processes are in the same network namespace
if and only if that symlink resolves to the same inode. This is precisely how
`docker network inspect`, CNI plugins, and `nsenter` figure out "which
namespace does this container belong to" — there's no namespace name or ID
registry beyond this inode identity; `ip netns` names are just a userspace
convenience built on bind-mounting these files somewhere findable.

The reason `lo` starts down in every fresh namespace (the gotcha from Step 3)
is that `struct net` creation doesn't special-case loopback bring-up — a new
namespace's `lo` device exists (the kernel always creates it) but its
`IFF_UP` flag is off by default, same as any other interface would be if you
created it from scratch. There's no "namespace initialization" step that
mirrors what your init system does for the host's `lo` at boot; each
namespace is genuinely empty of setup, and it's on you (or your container
runtime) to bring interfaces up.

## Where this shows up in the real world

Every container networking implementation — Docker's `docker0` bridge setup,
every Kubernetes CNI plugin (Calico, Cilium, Flannel), containerlab — is
built from exactly this pair of primitives: one `struct net` per container,
and veth pairs (or sometimes macvlan/ipvlan) crossing the boundary into a
bridge or the host. When a pod comes up with `ip route` output that looks
wrong, or a service is unreachable from one pod but not another, the fast
diagnosis is always "which namespace is this process actually in, and what
does the world look like from inside it" — `nsenter -t <pid> -n ip a` (used
directly in Lab 6) — rather than debugging from the host's view and assuming
it matches. Engineers who don't know namespaces are a distinct `struct net`
end up debugging routing tables and firewall rules on the wrong stack
entirely, because host `iptables -L` and container `iptables -L` can show
completely different rule sets that both look "empty" for different reasons.

## Go deeper

- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man7/network_namespaces.7.html — Michael Kerrisk's canonical reference for `network_namespaces(7)`, plus `namespaces(7)` for the general model and `setns(2)`/`unshare(2)` for the syscalls this lab exercises directly.
- **Book:** *The Linux Programming Interface* — Michael Kerrisk — the deepest treatment of namespace syscalls (`clone`, `unshare`, `setns`) and how they compose, from the same author as the man pages above.
- **Website/blog:** iximiuz Labs — https://iximiuz.com/en/posts/ — Ivan Velichko has several posts building container networking from raw namespaces and veth pairs upward; search the site for "network namespace" and "veth."
- **Website/blog:** Julia Evans' blog — https://jvns.ca — short, concrete posts on namespaces and debugging Linux networking from first principles; search for "network namespace."
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — practical walkthroughs of `ip netns`, veth pairs, and Linux networking administration.
