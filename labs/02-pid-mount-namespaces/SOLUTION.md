# Lab 2 — Solutions

## Challenge A — mount propagation leak

**Check:**
```bash
findmnt -o TARGET,PROPAGATION /
```
On most systemd-managed distros this shows `shared` for `/` (systemd runs
`mount --make-rshared /` early in boot). Then, after mounting tmpfs inside
the `unshare --mount` namespace, from a second host terminal:
```bash
findmnt /mnt
```
The tmpfs mount shows up on the host too.

**Diagnosis:** `unshare --mount` gives you a new mount namespace, but the
mounts inside it start out as members of the same "peer group" as the
mounts they were cloned from, if that parent mount's propagation type is
`shared`. A `shared` mount propagates every mount/unmount event to every
other member of its peer group — including peers outside your new
namespace, i.e. the host. Isolation from `unshare --mount` is not automatic;
it depends entirely on the propagation type of the mount you're branching
off of. This is precisely the bug class Kubernetes hit with kubelet:
without explicitly marking mounts `rslave` or `rprivate`, container mounts
(or host mounts) could leak across the boundary kubelet assumed was
isolated.

**Fix:**
```bash
sudo mount --make-rprivate /
sudo unshare --mount bash
mount -t tmpfs tmpfs /mnt
```
Making `/` (or the specific parent mountpoint) private before unsharing
breaks peer-group membership, so nothing done inside the new namespace can
propagate out. Clean up the leaked mount from Challenge A itself with
`sudo umount /mnt` on the host if it's still there.

**Lesson:** a new mount namespace is not automatically an isolated mount
namespace — propagation type governs whether mount events cross the
boundary, and the default on most modern distros is `shared`, not
`private`.

---

## Challenge B — ps shows it, kill can't touch it

**Check:**
```bash
sudo unshare --pid --fork bash
ps aux            # shows the full host process list
kill -0 <host_pid>
```
`kill -0` returns `No such process`, even though `ps aux` just printed that
exact PID with a real command name.

**Diagnosis:** `ps aux` and `kill` get their answers from two different
places. `ps` reads `/proc/[pid]` directory entries — and since this PID
namespace doesn't have its own mount namespace, `/proc` is still the host's
mount, so every host PID shows up. `kill(2)`, on the other hand, is a
syscall the kernel resolves using the CALLING process's own PID namespace:
it only recognizes PIDs that actually exist within that namespace. Your new
PID namespace only contains your shell and its children, so any PID `ps`
shows you that isn't one of those literally does not exist as far as
`kill()` is concerned — hence `ESRCH` / "No such process."

**Fix:** there's nothing to "fix" here — this is the correct, intended
kernel behavior. The takeaway is procedural: don't trust `/proc`-backed
tools (`ps`, `top`) to tell you what a namespaced process can actually
signal or interact with. If you need both correct listings and correct
signal semantics, you need a properly mounted `/proc` for that namespace
(`--mount-proc`) — that also makes `ps`/`kill` agree with each other.

**Lesson:** userspace introspection tools (`ps`, `top`) and the kernel's
own namespace-scoping (`kill`, `getpid`) can disagree because they read
from different sources — one from `/proc`, one from kernel-internal
namespace-relative PID resolution. Don't assume "I can see it" means "I can
touch it."
