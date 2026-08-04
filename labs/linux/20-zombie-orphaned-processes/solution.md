# Lab 20 — Solutions

## Challenge A — finding the leak among many processes

**Check:**
```bash
ps -eo pid,ppid,stat,cmd | awk '$3 ~ /^Z/ {print $2}' | sort | uniq -c | sort -rn
```

**Diagnosis:** this groups every zombie system-wide by its `PPID` and
counts them, which is exactly what you need when you can't just eyeball
one obviously-named process - in a real incident there could be dozens of
services running, and "which one is leaking" is the actual question, not
"is anything leaking." The output shows 3-4 PIDs (the original
`zombie_parent.py` plus the three extra copies from this challenge), each
with roughly 20 zombies under it. Cross-reference each `PPID` with
`ps -o cmd -p <ppid>` to identify what it actually is.

On the PID exhaustion question: `cat /proc/sys/kernel/pid_max` shows the
finite ceiling on the number of PIDs (process table slots) the kernel will
hand out at once - a zombie still holds one of those slots until its
parent calls `wait()` on it (the "process" is gone, but its process-table
*entry* isn't). An unbounded leak - a parent forking indefinitely and
never reaping - will eventually exhaust every free PID, at which point
*no new process of any kind* can start anywhere on the machine, not just
in the leaking service: `fork()` itself starts failing with `EAGAIN`
system-wide. This is a much bigger blast radius than "one broken service"
- it can take down everything on the host simultaneously.

**Fix:** kill or patch each identified leaking parent (same fix as the
main lab, applied to all of them):
```bash
pkill -9 -f zombie_parent
```

**Lesson:** in a real incident you rarely start out knowing which process
is responsible - `ps -eo pid,ppid,stat,cmd | awk '$3~/^Z/'` grouped by
`PPID` is the fast way to localize the actual offender(s) instead of
guessing, the same "count and localize before you act" principle used
elsewhere in this series for inode exhaustion and disk usage.

---

## Challenge B — telling zombies and orphans apart

**Check:**
```bash
ps -eo pid,ppid,stat,cmd | grep -E 'sleep 300|zombie_parent'
```
The `sleep 300` entry shows `PPID` of `1` (or your system's init-
equivalent PID) and `STAT` of `S` - alive, sleeping normally. The
`<defunct>` entries show `PPID` pointing at a `zombie_parent.py` process
that is itself still alive, and `STAT` of `Z`.

**Diagnosis:** the distinguishing signal is the `STAT` column, not the
`PPID` alone - a `PPID` of `1` on its own tells you the process was
reparented (its original parent died), but says nothing about whether
*this* process is alive or dead. `Z` means dead-but-unreaped, full stop,
regardless of what its `PPID` is. `S`/`R`/anything-not-`Z` under a `PPID`
of `1` means exactly what it looks like: a perfectly normal, running
process that happens to have been adopted by init/systemd after its
original parent exited.

Running `kill -9` on each:
- On the `sleep 300` (orphan, alive): it dies immediately, and because
  its parent is PID 1 / systemd (which does call `wait()` on everything
  it's responsible for), it's reaped right away too - you'll see it
  vanish from `ps` on the next check, no zombie stage lingers.
- On a `<defunct>` entry (zombie, already dead): nothing happens.
  `kill -9` returns success (the PID still exists as a table entry, so the
  syscall itself doesn't error), but there is no running task to deliver
  the signal to - a moment later, `ps` shows the exact same zombie,
  completely unaffected.

**Fix:** for the zombies, same as everywhere else in this lab - fix or
kill the *parent*, not the zombie itself:
```bash
pkill -9 -f zombie_parent
```

**Lesson:** "reparented to init" (orphan) and "not yet reaped" (zombie)
are unrelated axes - a process can be reparented AND alive (this
challenge's `sleep 300`), reparented AND a zombie (briefly, in the instant
before init/systemd reaps it - which happens almost immediately, so you
rarely catch this state in the wild), or neither. The only column that
tells you "is this actually dead" is `STAT`'s `Z`. Never assume a `PPID`
of `1` means "safe to ignore" or "already handled" - check `STAT` before
concluding anything.
