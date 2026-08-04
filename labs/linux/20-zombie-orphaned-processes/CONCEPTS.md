# Lab 20 — Concept: Zombies, Orphans, and Why the Kernel Keeps Dead Processes Around at All

## What's actually going on

When a process exits, the kernel doesn't immediately discard everything
about it. It keeps a small process-table entry - just the PID, exit
status, and resource usage totals - specifically so the parent can later
call `wait()`/`waitpid()` and retrieve that exit status. This waiting
period is what `ps` reports as state `Z` (zombie, shown as `<defunct>` in
the command column): the process has already terminated, all of its
memory and file descriptors have been released, and the only thing left
is that one small record, held open purely so a `wait()` call has
something to collect. If the parent never calls `wait()` - as this lab's
buggy `zombie_parent.py` never does - that record just sits there
indefinitely. This is why `kill -9` on a zombie is a complete no-op: `kill`
delivers a signal to a running task so its scheduler state can react to
it, and a zombie has no running task at all, just a table entry. The
syscall itself doesn't even error (the PID still technically exists), it
simply has nothing to act on. The only way to make a specific zombie go
away is for its parent to actually call `wait()` on it, or for the parent
to die (at which point the zombie, still unreaped, gets reparented and
reaped by whoever adopts it, as described below).

An **orphan** is a completely different situation that happens to share
some vocabulary: it's what happens to a *still-running* child when its
parent dies *first*, before the child exits. The kernel's answer is
reparenting - the orphaned child gets handed to a new parent, traditionally
PID 1 (`init`), though on modern Linux systems any ancestor process can
register itself as a "child subreaper" via `prctl(PR_SET_CHILD_SUBREAPER)`
to claim this role instead (systemd does this for certain scopes). The
crucial point: at the moment of reparenting, the orphan is completely
ordinary and alive - `S`/`R`/whatever state it was already in, doing
whatever it was already doing, just with a new `PPID`. It only becomes
relevant to zombie-cleanup at all because its new parent (init/systemd)
*does* call `wait()` on everything under it, which is precisely why a
zombie that gets reparented (because its original, buggy parent died)
gets reaped almost instantly by its new parent - you'll rarely catch a
reparented process sitting in `Z` state for long, unlike a zombie stuck
under a parent that's alive but simply never reaping.

This is exactly why "zombie" and "orphan" are so often confused despite
describing opposite conditions: a `PPID` of `1` can mean either "this
orphan is alive and being properly supervised by init" or "this was a
zombie whose bad parent just died and it's about to be cleaned up" - the
*only* column that disambiguates is `STAT`. The practical operational
consequence follows directly from this mechanism: since zombies are
literally not signalable, the only real fixes are (1) fix the parent's
code so it actually reaps its children (the durable fix), or (2) kill or
restart the parent so its zombies get reparented and reaped by init/
systemd instead (a working but blunt emergency measure - whatever else
that parent was doing also stops). And because each zombie still occupies
a slot in the kernel's finite PID namespace until reaped, an unbounded
leak isn't just cosmetic clutter in `ps` output - left running long
enough, it's a path to full PID exhaustion (`fork()` failing with `EAGAIN`
system-wide), which is a whole-machine outage, not a single-service one.

## Where this shows up in the real world

Any long-running supervisor, worker-pool manager, or shell script that
backgrounds subprocesses (`&`) without ever collecting their exit status
is a zombie leak waiting to happen - this is a genuinely common bug in
hand-rolled process supervisors, older init scripts, and container
entrypoints that spawn multiple processes without a proper init/reaper
(this is exactly why `tini`, `dumb-init`, and Docker's `--init` flag
exist: PID 1 inside a container has to do real reaping, and a container's
main process rarely bothers to). The orphan side shows up constantly and
harmlessly in everyday shell use - any backgrounded job (`cmd &`) whose
parent shell exits before the job finishes becomes an orphan, reparented
and still running fine, which is normal and expected, not a bug. The
confusion between the two costs real debugging time: someone sees a
`<defunct>` process, tries to `kill -9` it, concludes the system is
broken when nothing happens, when the actual, simple fix was one level up
the process tree the entire time.

## Go deeper

- **Book:** *The Linux Programming Interface* — Michael Kerrisk — has a
  detailed, authoritative treatment of process termination, `wait()`/
  `waitpid()` semantics, zombies, and orphan reparenting - this lab is
  built directly on that material.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man2/wait.2.html
  — canonical `wait(2)`/`waitpid(2)` reference, including the exact
  zombie-creation and reaping semantics.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man7/signal.7.html
  and https://man7.org/linux/man-pages/man2/prctl.2.html (`PR_SET_CHILD_SUBREAPER`)
  — signal delivery semantics (why zombies can't receive them) and the
  subreaper mechanism systemd uses for reparenting.
- **Website/docs:** Arch Linux Wiki — https://wiki.archlinux.org — has
  practical process-management troubleshooting pages covering `ps` STAT
  column interpretation.
- **Book:** *Systems Performance* — Brendan Gregg — general methodology
  for diagnosing resource-exhaustion classes of bugs (PID exhaustion
  included) before they become full outages.
