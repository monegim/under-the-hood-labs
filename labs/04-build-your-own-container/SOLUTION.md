# Lab 4 — Solutions

## Challenge A — proc mounted in the wrong place

**Check:**
```bash
ps aux
mount | grep proc
```
`ps aux` inside the chroot shows nothing useful (empty or an error like
`ps: can't open /proc`), even though you're clearly in a new PID namespace
(`echo $$` still shows 1).

**Diagnosis:** `unshare --mount-proc` (without an explicit path) mounts
procfs at the DEFAULT path, `/proc`, and it does this BEFORE executing the
command you gave it — which in this case is `chroot`. At the moment the
mount happens, you have not chrooted yet, so `/proc` refers to the HOST
filesystem's `/proc` path (inside your new, but still host-rooted, mount
namespace). Then `chroot` swaps the root to `$ROOTFS` — and the procfs
mount you just created is left behind on the old root, nowhere near the
`$ROOTFS/proc` directory that is now `/proc` from inside the chroot. You
end up with a correctly-scoped PID namespace but an empty, unmounted
`/proc` inside the container — the mirror image of Lab 2's original
gotcha, just relocated by the chroot.

**Fix:** either pass the mountpoint explicitly so it lands inside the
future chroot (`--mount-proc=$ROOTFS/proc`, as in Step 3), or mount procfs
yourself AFTER the chroot has already happened, from inside the container
shell:
```bash
mount -t proc proc /proc
```

**Lesson:** when you combine `chroot` with namespace setup, ordering and
path matter — anything mounted before the `chroot` call is relative to the
OLD root, not the new one. "Where does this mount end up" depends entirely
on when in the pipeline the mount happens relative to the root switch.

---

## Challenge B — limits that silently don't apply

**Check:**
```bash
CONTAINER_PID=$(pgrep -f "chroot $ROOTFS")
cat /proc/$CONTAINER_PID/cgroup
cat /sys/fs/cgroup/mycontainer2/cgroup.procs
```
The container process's `/proc/<pid>/cgroup` still points at the ROOT
cgroup (or whatever cgroup your shell was already in), not
`mycontainer2`. `cgroup.procs` for `mycontainer2` is empty.

**Diagnosis:** creating a cgroup and writing `memory.max` to it only
prepares the limit — it does nothing on its own. A cgroup only constrains
processes that have actually been added to its `cgroup.procs`. Unlike Lab
3 and Step 4 of this lab, this variant never wrote the container's PID
into `mycontainer2/cgroup.procs`, so the limit exists but is attached to
nobody. The container process keeps running wherever it was before
(typically the root cgroup, which usually has no limits), so it can
allocate memory freely regardless of what `memory.max` says in a cgroup it
was never joined to.

**Fix:**
```bash
echo $CONTAINER_PID | sudo tee /sys/fs/cgroup/mycontainer2/cgroup.procs
```
Then re-run the memory-hungry command inside the container — now it's
actually a member of the limited cgroup and gets OOM-killed as expected.

**Lesson:** setting a limit and applying a limit are two separate steps in
cgroup v2. A `memory.max` file with a value in it tells you nothing about
whether anything is actually being constrained by it — always check
`cgroup.procs` (or `/proc/<pid>/cgroup` from the process side) before
trusting that a limit is in effect.
