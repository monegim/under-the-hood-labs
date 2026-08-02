# Lab 2 — Concept: PID + Mount Namespaces

## What's actually going on

A PID namespace changes what `getpid()`, `kill()`, and process tree walking
mean for the processes inside it — it does not change what files exist on
disk. Internally, a process's PID is not a single number: `task_struct` holds
a `struct pid` that carries one numeric ID per PID-namespace-nesting-level the
process is visible in. When you `unshare(CLONE_NEWPID)`, the kernel doesn't
give your shell a new number in the same table — it creates a genuinely new,
nested numbering, and your shell becomes PID 1 *within that namespace* while
still holding some other, larger PID in the parent (host) namespace's table.
That's why `echo $$` prints `1` — the kernel is not lying — but that `1` is
scoped to a namespace, not a global truth.

This has a very specific consequence Lab 2's Step 1 vs Step 2 is built
around: PID 1 in a PID namespace is not just "the first process," it inherits
init's special responsibilities within that namespace — specifically,
orphaned children get reparented to it, and if it dies, the kernel tears
down the whole namespace (sends SIGKILL to everything else in it). This is
why container runtimes care so much about what runs as PID 1 inside a
container, and why people run tiny init shims like `tini` or `dumb-init` —
without one, an application that doesn't reap zombies can leave defunct
processes piling up with nothing to collect them.

The Step 2 gotcha (`ps aux` showing the whole host) is the core lesson: `ps`
does not ask the kernel "list the processes in my namespace" — it opens
`/proc` and reads the numbered directories it finds there (`/proc/1`,
`/proc/2`, ...). Which entries actually show up under `/proc` is controlled
by *which procfs mount* you're looking through, and that's a mount-namespace
question, completely orthogonal to which PID namespace you're in. `unshare
--pid` alone leaves you sharing the host's mount namespace, so `/proc` is
still the host's procfs — which walks `struct pid` from the *initial* PID
namespace and shows every host process, decorated with data even your new
namespace's processes will report on. Meanwhile `kill(2)` is resolved
kernel-side by looking up the target PID against the *calling process's own*
PID namespace — it never consults `/proc` at all — so a PID `ps` printed from
the host's procfs can be completely unresolvable to `kill` if it doesn't
exist in your namespace's private numbering. Two different code paths, two
different sources of truth, and no reason in general for them to agree unless
you also privatized the mount namespace and remounted `/proc` — which is
exactly what `--mount-proc` automates: implicitly `unshare(CLONE_NEWNS)` too,
then `mount -t proc proc /proc` before exec'ing your command, so the `/proc`
inside is a fresh instance that only walks your new PID namespace's tree.

Mount namespaces work on a structurally similar idea, but for the mount
table instead of the process table: the kernel keeps mounts as a tree of
`struct mount` objects, and each mount namespace has its own root of that
tree (`struct mnt_namespace`). `unshare(CLONE_NEWNS)` clones the current
mount tree into a new namespace — you start with a copy of everything
currently mounted, but from that point forward, `mount`/`umount` calls made
in one namespace don't have to be seen by another. The word "have to" is
doing a lot of work there: whether they're seen depends on mount
*propagation type*, a per-mount property (`shared`, `private`, `slave`,
`unbindable`) that determines whether mount/unmount events cross between
"peer" mounts that were cloned from a common ancestor. systemd sets `/` to
`shared` early in boot specifically so that things like removable media
mounted in one context show up everywhere — but that same default means a
freshly unshared mount namespace isn't automatically isolated; its mounts are
still peers of the host's, and events propagate both ways, until you mark
something `private` (or `rslave`, one-way) with `mount --make-rprivate` /
`--make-rslave`. This is exactly the distinction Challenge A is built to
surface, and it's not a corner case — it's the literal bug class Kubernetes'
kubelet had to explicitly engineer around for hostPath mounts.

## Where this shows up in the real world

Every container runtime (runc, containerd, CRI-O) creates both a new PID
namespace and a new mount namespace for every container, and always mounts a
fresh procfs after the mount namespace is set up — skipping that second part
is a real bug class in homegrown sandboxing/jail tooling, and it's exactly
what changes when someone runs `docker run --pid=host`: the container gets
its own filesystem view but suddenly `ps` inside it sees every host process,
because now it's sharing the *mount* namespace's `/proc` view, not because
PID isolation broke. On the mount-propagation side, `kubelet`'s hostPath
volume handling and CSI driver mount plumbing both have to reason explicitly
about `shared`/`rslave`/`rprivate` propagation to avoid leaking bind mounts
between containers and the host — when a mount shows up somewhere it
shouldn't (or vanishes when a container is removed), the fast diagnosis is
`findmnt -o TARGET,PROPAGATION` on the relevant mountpoints, not blind
`strace`-based guessing.

## Go deeper

- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man7/pid_namespaces.7.html — canonical reference for `pid_namespaces(7)`; also see `mount_namespaces(7)` on the same site for the propagation-type semantics behind Challenge A.
- **Book:** *The Linux Programming Interface* — Michael Kerrisk — detailed treatment of namespaces, `/proc`, and process/file semantics that underlies both halves of this lab.
- **Website/docs:** Linux kernel docs on shared subtrees — https://docs.kernel.org/filesystems/sharedsubtree.html — the authoritative explanation of `shared`/`private`/`slave`/`unbindable` propagation types referenced in Challenge A.
- **Website/blog:** Julia Evans' blog — https://jvns.ca — has concrete, hands-on posts specifically about the "`ps` shows it but PID namespace doesn't have it" class of confusion; search for "PID namespace" and "procfs."
- **Website/blog:** iximiuz Labs — https://iximiuz.com/en/posts/ — builds PID/mount namespace mechanics from scratch with the same "do it by hand first" approach as this lab.
