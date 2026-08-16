# Lab 13 — Solutions

## Challenge A — `soft` vs `hard`, and what each one actually costs you

**Check:**
```bash
timeout 15 cat /mnt/nfslab13/data.txt; echo "exit code: $?"
```
On the default `hard` mount, the `cat` never returns before the
`timeout` kills it — exit code 124. On a `soft` mount with `timeo=30`
(3 second units → ~3s per retry) and `retrans=2`, the same access
returns an actual I/O error in a few seconds — exit code 1 (or similar),
not a hang.

**Diagnosis:** `hard` (the default) means the client retries an NFS
request forever, uninterruptibly, until the server responds — the
underlying assumption being that whatever's wrong is transient and the
operation *must* eventually succeed, because giving up silently could
mean silently losing data. `soft` means the client gives up after
`timeo`/`retrans` and returns `EIO` to the calling process instead. That
sounds strictly better from where you're sitting during this exercise —
but the tradeoff is real: with `soft`, a *write* that times out can
return an error to the application after the data was already
partially — or even fully — transmitted, with no reliable way for the
application to know whether the server actually got it or not. That's
why NFS documentation has historically recommended `hard` specifically
for anything doing writes you care about, and `soft` is more defensible
for read-mostly mounts (package repos, static asset shares) where a
timeout just means "try again," not "did I just silently lose data."

**Fix:** there isn't a universal answer — the point of this challenge
is picking deliberately, not defaulting to whichever hangs less. For
reads-only or non-critical mounts, `soft` with sane `timeo`/`retrans`
avoids indefinite hangs. For anything doing writes that must not be
silently lost, stay `hard`, and instead make the *timeout characteristics*
tunable (or address the real availability problem) rather than trading
away durability to avoid hangs.

**Lesson:** "hangs forever" (hard) and "fails fast" (soft) are not
"bad" and "good" — they're two different answers to "what should happen
when I genuinely can't tell if my write succeeded," and the right
choice depends entirely on whether losing that write silently is worse
than a stuck process. Don't reach for `soft` purely to make hangs go
away without weighing what it actually gives up.

---

## Challenge B — when `umount -f` isn't enough either

**Check:**
```bash
sudo umount -f /mnt/nfslab13; echo "exit code: $?"
```
This can itself hang or return `device or resource busy` — with a
process genuinely blocked inside the kernel on an unreachable hard
mount, `umount -f` still has to coordinate with that blocked operation,
and it may not be able to cleanly finish while the operation is
uninterruptibly stuck.

**Diagnosis:** `umount -f` forces an NFS unmount at the protocol level
(stops retrying server requests, returns errors to already-pending
calls where it can) — but "already-pending calls" that are stuck in
`TASK_UNINTERRUPTIBLE` (D-state, the same mechanism as
`linux/09-process-stuck-in-d-state`) inside the kernel aren't always
something `umount -f` can immediately unstick, because that process is
not currently interruptible by anything, including the unmount attempt
itself.

**Fix:**
```bash
sudo umount -l /mnt/nfslab13; echo "exit code: $?"
```
`umount -l` ("lazy unmount") detaches the mount point from the
filesystem namespace *immediately* — you get your shell back right
away, `mount` no longer lists it, new opens against that path go
elsewhere — without waiting for existing references (like the blocked
`cat`) to actually finish. The blocked process is still blocked, still
holding its reference to the now-detached mount, and will resolve
(error out or complete) whenever the underlying I/O finally does — lazy
unmount doesn't fix that process, it just stops making everyone else
wait on it.

**Lesson:** `-f` (force) and `-l` (lazy) solve different problems and
aren't interchangeable — `-f` tries to make the underlying operation
actually stop/fail; `-l` gives up trying to coordinate with in-flight
operations at all and detaches the namespace entry regardless. When a
process is genuinely stuck in D-state on the old mount, `-l` is often
the only thing that gets your terminal back — but the stuck process
itself still needs to be dealt with separately (it'll resolve on its
own once the I/O it was blocked on finally times out or completes).
