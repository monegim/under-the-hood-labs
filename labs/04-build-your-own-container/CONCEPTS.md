# Lab 4 — Concept: Build Your Own Container

## What's actually going on

The core thing this lab proves is that "a container" is not a kernel object
at all — there is no `struct container` anywhere in the Linux kernel. A
container is a regular process wrapped in a specific *combination* of
independent, general-purpose mechanisms: namespaces to change what it can
see, a filesystem swap to change what root looks like, and a cgroup to cap
what it can consume. `runc` (the low-level runtime underneath Docker,
containerd, and CRI-O) is, structurally, this exact script, generalized and
hardened: it reads a config describing which namespaces to unshare, which
rootfs to use, and which cgroup limits to apply, then does the syscall
sequence by hand — `clone()`/`unshare()` with a bitmask of `CLONE_NEWPID |
CLONE_NEWNS | CLONE_NEWUTS | CLONE_NEWNET | ...`, a root filesystem switch,
writing PIDs into `cgroup.procs` — and finally `execve()`s the container's
actual entrypoint. Nothing about "container start" is atomic or magic; it's
an ordered sequence of ordinary syscalls, and the order matters enormously,
which is exactly what both challenges in this lab are testing.

`chroot` versus `pivot_root` is worth being precise about, since production
runtimes deliberately don't use what this lab uses. `chroot(path)` just
changes the calling process's idea of `/` for path-resolution purposes — it
does not unmount the old root, does not require the old root to become
unreachable, and critically, it doesn't need a mount namespace to work at
all (it predates namespaces by decades and is a single simple syscall).
That simplicity is also its weakness: a process with enough privilege can
sometimes escape a plain chroot by exploiting the fact that the old
filesystem tree is still reachable through open file descriptors or
relative-path games. `pivot_root(new_root, put_old)`, which `runc` actually
uses, is a mount-namespace-aware operation — it swaps which mount is the
namespace's root and moves the old root to `put_old`, so it can then be
unmounted or detached entirely, making the old filesystem tree genuinely
inaccessible rather than just currently-not-the-default. `pivot_root`
requires a private mount namespace to make sense (you're changing which
mount is "the root" for that namespace specifically), which is precisely why
this lab's approach (chroot, no dedicated mount-namespace root swap) is
explicitly called out as the simplified, less secure version.

The ordering gotcha in Challenge A — `--mount-proc` without an explicit path
lands procfs on the *old* root, not inside the rootfs — exists because
`unshare` performs the mount before executing your command (`chroot` in this
case), and at that moment "/proc" unambiguously means the host's `/proc`
path, since chroot hasn't happened yet. This is a general truth about
building containers by hand: every mount you set up is relative to whatever
root is currently active *at the moment the mount syscall runs*, not
whatever root will be active later in the pipeline. Production runtimes
solve this by controlling the exact ordering internally (set up the
namespaces and rootfs mounts first, `pivot_root`, mount procfs into the
*new* root, then exec) rather than composing pre-existing CLI tools like
this lab does — the manual version makes that ordering dependency visible
instead of hiding it inside a runtime's internal logic.

Challenge B's lesson — a cgroup with a limit set but no member PIDs enforces
nothing — connects back to something easy to gloss over from Lab 3: a
cgroup directory and its interface files (`memory.max`) are just
configuration sitting on disk. The kernel only consults that configuration
when it's charging pages or scheduling CPU time *for a process that is
actually a member of that cgroup* (i.e., present in `cgroup.procs`, which is
resolved via the process's `task_struct` pointing at its `css_set`).
Creating the cgroup and writing the limit is necessary but not sufficient;
membership is a separate, explicit step, and a container runtime has to get
both steps right, and in the right order relative to when the container's
process actually starts running, or the container runs with no enforcement
at all while `docker stats`/`kubectl describe` may still report a limit that
looks configured.

## Where this shows up in the real world

This is literally what `runc create` + `runc start` do when Docker or a
Kubernetes CRI shim asks for a new container: assemble a rootfs (usually an
overlayfs stack, Lab 5's subject), unshare a namespace set, `pivot_root`,
mount a fresh `/proc`, and add the resulting process to a pre-configured
cgroup — this lab is that sequence with the training wheels of proper
security hardening (seccomp filters, Linux capabilities dropping, read-only
bind mounts) removed so the mechanism is visible. Debugging "container
starts but resource limits aren't applied," or "container's `/proc` shows
host processes," or "container escapes its supposed root" all reduce to
checking exactly the things this lab's challenges force you to check:
ordering of mount vs. chroot/pivot_root, and cgroup membership vs. cgroup
configuration — the kind of engineer who's built this by hand once
diagnoses these in minutes by checking `/proc/<pid>/cgroup` and `mount`
output, instead of guessing at the runtime's internals for hours.

## Go deeper

- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man2/pivot_root.2.html — the `pivot_root(2)` man page, essential for understanding exactly why it differs from `chroot(2)` (linked from the same site).
- **Book:** *The Linux Programming Interface* — Michael Kerrisk — covers `chroot`, namespaces, and process/file semantics that this lab combines end to end.
- **Book:** *Container Security* — Liz Rice — walks through exactly this "container is just namespaces + chroot/pivot_root + cgroups" model from a security-hardening angle, covering the gaps this lab deliberately leaves open (capabilities, seccomp).
- **Website/blog:** iximiuz Labs — https://iximiuz.com/en/posts/ — Ivan Velichko has posts and small projects building a container runtime from scratch in the same spirit as this lab; search for "build your own container" / "runc internals."
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — practical Linux internals content that helps ground the individual primitives (namespaces, chroot, cgroups) this lab assembles.
