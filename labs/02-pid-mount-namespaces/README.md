# Lab 2 — PID + Mount Namespaces

## Objective
Build a PID namespace and see why it isn't enough on its own, then build a
mount namespace and prove it gives you a private view of the filesystem
table. Understand that "process isolation" and "`/proc` reflecting that
isolation" are two separate mechanisms.

## Why this matters
Every container runtime (runc, containerd, CRI-O) creates a new PID
namespace for a container AND mounts a fresh `/proc` inside it. If you skip
the second part, `ps`/`top` inside the container leak the host's full
process list — a real bug class in home-grown sandboxing code and a thing
to know when you see `--pid=host` in a `docker run` command and wonder what
it actually changes. Mount namespaces are the mechanism behind container
filesystems, `kubectl exec`, and also behind a nasty class of bugs: mount
propagation leaks between containers and the host.

## Prerequisites
- Same VM as Lab 1, `util-linux`'s `unshare`/`nsenter`
- `sudo` access

Check first:
```bash
which unshare nsenter ps findmnt
unshare --pid --fork --mount-proc true && echo ok
```

## Step 1 — PID namespace, done right
```bash
sudo unshare --pid --fork --mount-proc bash
```
Inside:
```bash
echo $$
ps aux
```
`$$` shows `1` — your shell is PID 1 in this namespace. `ps aux` shows only
your shell and `ps` itself. Exit (`exit`) to get back to the host shell.

## Step 2 — PID namespace, done wrong (the actual lesson)
```bash
sudo unshare --pid --fork bash
```
Inside:
```bash
echo $$
ps aux
```
Look closely at what `ps aux` prints.

> Gotcha: `$$` still shows `1` — the kernel really did give you a new PID
> namespace, and your shell really is PID 1 in it. But `ps aux` shows the
> HOST's full process list, not just your shell. `unshare --pid` alone does
> not create a new mount namespace, so `/proc` is still the host's `/proc`
> mount. `ps` doesn't ask the kernel "what's in my PID namespace" — it reads
> `/proc/[pid]` entries directly, and every one of the host's PIDs is still
> sitting there. PID namespace isolation and `/proc` reflecting that
> isolation are two independent mechanisms; you need both.

Do not try to fix this by running `mount -t proc proc /proc` here — you're
still in the host's mount namespace, so that would replace `/proc` for the
entire host, not just this shell. The real fix is to combine `--pid` with a
new mount namespace, which is exactly what `--mount-proc` did for you in
Step 1 (it implies a new mount namespace and mounts a fresh procfs into it
before running your command). Exit back to the host.

## Step 3 — Mount namespace on its own
```bash
sudo unshare --mount bash
```
Inside:
```bash
mkdir -p /mnt/nsdemo
mount -t tmpfs tmpfs /mnt/nsdemo
echo "only visible inside this namespace" > /mnt/nsdemo/secret.txt
cat /mnt/nsdemo/secret.txt
```
Leave this shell running. Open a second terminal on the host (don't exit
the namespace shell) and check:
```bash
findmnt /mnt/nsdemo
ls /mnt/nsdemo
```
The host sees neither the mount nor the file — the mount table itself is
namespaced, and this one only exists inside your new namespace.

> Gotcha: this only works cleanly because the mount you created doesn't
> propagate back to the host. By default on most systemd-based distros, `/`
> is mounted with "shared" propagation, which means mount/unmount events
> CAN cross between a shared namespace and its peers (including the host).
> Whether you get isolation here depends on the propagation type of the
> parent mount — see Challenge A.

## Step 4 — Attach to a running mount namespace
```bash
sudo unshare --mount sleep 100 &
ls -la /proc/$!/ns/
sudo nsenter --mount=/proc/$!/ns/mnt bash
findmnt /mnt/nsdemo 2>/dev/null || echo "not visible from this shell"
```
That `mnt` symlink under `/proc/<pid>/ns/` is exactly what `nsenter` and
`docker exec` use to attach to a running container's mount namespace.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — mount propagation leak:**
```bash
sudo unshare --mount bash
mount -t tmpfs tmpfs /mnt
```
(No `--make-rprivate` beforehand.) From a second host terminal:
```bash
findmnt /mnt
```
Compare this to Step 3 — is the mount visible on the host this time? Check
the propagation type of `/` on your system before you decide this is a bug:
```bash
findmnt -o TARGET,PROPAGATION /
```
This is the exact bug class behind Kubernetes kubelet/hostPath mount leaks
(kubelet has to explicitly set mount propagation to avoid exactly this).
Figure out what's different from Step 3 and how you'd prevent it.

**Challenge B — confusing the PID-namespace-without-proc gotcha:**
```bash
sudo unshare --pid --fork bash
ps aux
```
Pick a PID from the list that clearly belongs to a real host process (e.g.
`sshd`, `systemd`, or any long-running daemon) and try:
```bash
kill -0 <that_pid>
```
Reconcile what `ps aux` told you exists with what `kill` just told you.

See `SOLUTION.md` only after you've formed your own diagnosis.
