# Lab 4 — Build Your Own Container

## Objective
Combine everything from Labs 1–3 — namespaces (PID, mount, UTS, net) +
`chroot` + cgroups — into one script that runs a process in something that
behaves like a minimal container. This is the capstone of Track 1.

## Why this matters
This is, minus a long list of edge cases and security hardening, what
`runc` does when Docker or Kubernetes's container runtime "creates a
container": pick/build a root filesystem, `chroot`/`pivot_root` into it,
unshare a set of namespaces, mount a fresh `/proc`, and drop the resulting
process into a cgroup with resource limits. Once you've built this by hand
you'll never look at "container" as a magic kernel object again — it's a
regular process with some kernel bookkeeping around it.

## Prerequisites
- Completed Labs 1–3 (namespaces, mount namespaces, cgroups)
- `busybox-static` for a tiny, dependency-free root filesystem
- `sudo` access

Check first:
```bash
which unshare nsenter chroot
sudo apt-get update && sudo apt-get install -y busybox-static
stat -fc %T /sys/fs/cgroup   # expect cgroup2fs
```

## Step 1 — Build a minimal root filesystem
We don't need a full distro rootfs — a statically linked BusyBox gives us
`sh`, `ls`, `ps`, `mount`, `hostname`, and dozens of other applets as one
binary.
```bash
ROOTFS=$HOME/mycontainer/rootfs
mkdir -p $ROOTFS/{bin,proc,sys,dev,etc}
cp $(which busybox) $ROOTFS/bin/busybox
$ROOTFS/bin/busybox --install -s $ROOTFS/bin
ls $ROOTFS/bin | head
```
You now have a self-contained `bin/` directory full of symlinks to
`busybox`, including `sh`.

## Step 2 — Set up the cgroup (from Lab 3)
```bash
CGROUP=/sys/fs/cgroup/mycontainer
sudo mkdir -p $CGROUP
echo "+memory +cpu +pids" | sudo tee /sys/fs/cgroup/cgroup.subtree_control
echo $((100*1024*1024)) | sudo tee $CGROUP/memory.max
echo "50000 100000" | sudo tee $CGROUP/cpu.max
```
100 MiB memory, 50% of one CPU — same mechanism as Lab 3, just prepared
ahead of time for the process we're about to launch.

## Step 3 — Launch into namespaces + chroot (from Labs 1 & 2)
```bash
sudo unshare --pid --fork --mount --uts --net \
  --mount-proc=$ROOTFS/proc \
  chroot $ROOTFS /bin/sh
```
Notice we pass `--mount-proc=$ROOTFS/proc` with an explicit path, not the
default. `unshare` mounts procfs at that path BEFORE it execs `chroot`, so
by the time `chroot` swaps the root filesystem, the freshly mounted procfs
is already sitting exactly where `/proc` will be once you're inside.

Inside the shell:
```bash
echo $$
ps aux
hostname mycontainer
hostname
ip link 2>/dev/null || echo "no ip applet in this busybox build"
```
`$$` is 1 (new PID namespace), `ps aux` shows only this shell (proc is
correctly scoped this time — this is Lab 2's lesson, done right), and
`hostname mycontainer` only changes the hostname inside this UTS namespace
— it won't affect the host. Leave this shell running; move to a second
terminal for the next step.

> Gotcha: the network namespace here starts completely empty except a
> DOWN `lo` interface — exactly like Lab 1's fresh namespaces. This
> "container" currently has no connectivity. Giving it real connectivity
> means plugging in a veth pair the same way Lab 1 did — that's a natural
> extension of this lab, not required for what follows.

## Step 4 — Move the container's real (host) PID into the cgroup
Cgroups operate on real, host-visible PIDs — never namespaced PIDs like the
`1` you saw in Step 3. From the second terminal:
```bash
CONTAINER_PID=$(pgrep -f "chroot $HOME/mycontainer/rootfs")
echo $CONTAINER_PID
echo $CONTAINER_PID | sudo tee /sys/fs/cgroup/mycontainer/cgroup.procs
cat /proc/$CONTAINER_PID/cgroup
```
That last command, read from the HOST's `/proc`, confirms the process is
now a member of `mycontainer`.

## Step 5 — Prove the limits are real
Back in the container shell (terminal 1):
```bash
busybox free 2>/dev/null || cat /proc/meminfo | head -3
```
From terminal 2, generate load against the cgroup the same way as Lab 3
(`stress-ng`, or anything memory/CPU hungry) targeting `$CONTAINER_PID`'s
cgroup, and confirm via `cat /sys/fs/cgroup/mycontainer/memory.events` /
`cpu.stat` that the limits set in Step 2 are being enforced against
whatever runs inside the chroot+namespaces from Step 3.

## Step 6 — Clean up
```bash
exit   # leave the container shell
sudo rmdir /sys/fs/cgroup/mycontainer
```

## What you just built
- **chroot** — filesystem isolation (Docker image root)
- **PID namespace + fresh /proc** — process tree isolation (Lab 2)
- **mount namespace** — private mount table (Lab 2)
- **UTS namespace** — private hostname (new here)
- **net namespace** — private (empty) network stack (Lab 1)
- **cgroup** — resource limits (Lab 3)

That's the whole list of primitives `runc` assembles per container, plus
`pivot_root` instead of `chroot` in production (more secure, harder to
escape) and a lot of default security hardening (seccomp, capabilities,
read-only mounts) this lab deliberately skips to keep the mechanism
visible.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — proc mounted in the wrong place:**
```bash
sudo unshare --pid --fork --mount --uts --net --mount-proc \
  chroot $ROOTFS /bin/sh
```
(Same as Step 3, but drop the `=$ROOTFS/proc` argument — just bare
`--mount-proc`.) Inside the resulting shell:
```bash
ps aux
mount | grep proc
```
Compare this to Step 3's behavior and figure out exactly where the procfs
mount actually ended up, and why it doesn't show up where you need it.

**Challenge B — limits that silently don't apply:**
```bash
sudo mkdir -p /sys/fs/cgroup/mycontainer2
echo "+memory" | sudo tee /sys/fs/cgroup/cgroup.subtree_control
echo $((20*1024*1024)) | sudo tee /sys/fs/cgroup/mycontainer2/memory.max
sudo unshare --pid --fork --mount --uts --net \
  --mount-proc=$ROOTFS/proc chroot $ROOTFS /bin/sh
```
Run something memory-hungry inside this container and expect it to get
OOM-killed at 20 MiB. It doesn't. Check `/proc/<pid>/cgroup` for this
process from the host, and `cat /sys/fs/cgroup/mycontainer2/cgroup.procs`,
before concluding whether the limit is even attached to anything.

See `SOLUTION.md` only after you've formed your own diagnosis.
