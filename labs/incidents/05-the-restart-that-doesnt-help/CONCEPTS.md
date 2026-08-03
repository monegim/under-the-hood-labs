# Incident 05 — Concept: Why "Restart It" Has Limits, and What D State Actually Means

## What's actually going on

The core Linux mechanism is `TASK_UNINTERRUPTIBLE` sleep - `D` state in
`ps`'s `STAT` column. A process enters it when it's blocked inside a
kernel-space syscall (usually I/O) that the kernel has decided must not
be interrupted by a signal before it completes, because doing so could
leave kernel data structures (or the filesystem, or the device) in an
inconsistent state. `SIGKILL`, normally the unconditional "make it stop"
signal, is only *delivered* when the kernel next checks for pending
signals on that task - and for a task in `D` state, that check doesn't
happen until the blocking syscall itself returns. The signal isn't
ignored; it's queued, waiting for a scheduling opportunity that hasn't
arrived yet. This is precisely why `kill -9` - the tool every engineer
reaches for as an absolute last resort - can visibly do nothing at all
here, which is disorienting the first time you see it.

The second mechanism is what this incident adds on top of the D-state
lesson (from `labs/linux/09-process-stuck-in-d-state`): the specific,
very common failure of a systemd-managed *service*, not a bare process.
`systemctl restart` is not a magic "make the old thing go away and start
a fresh one" operation - it's SIGTERM, a wait, then SIGKILL, exactly the
same signal-based toolkit that fails against a D-state task. Restarting
a service whose main process is blocked in D state doesn't fail
loudly - it just takes a long time (waiting through the stop timeout)
and may leave systemd's bookkeeping out of sync with reality: if the
stop sequence times out, systemd may consider the unit stopped and start
a fresh instance, while the *original* process - still blocked, still
holding whatever resource (here, an NFS mount) it was blocked on - keeps
existing in the background, invisible to `systemctl status` (which now
only knows about the new instance) but very visible to `ps`. This is
why "restarting doesn't help" is itself diagnostic: an on-call who knows
this pattern immediately suspects a D-state block, rather than assuming
the restart "just needs to be tried again" a third time.

## Where this shows up in the real world

Every SRE eventually hits a process that refuses to die no matter what
signal is sent - it is almost always this exact mechanism: blocked
kernel-space I/O against a hung NFS/SAN/iSCSI target, a failing disk, or
a stuck device driver, never a process "ignoring" signals in userspace.
Kubernetes pods stuck in `Terminating` indefinitely are one of the most
common real-world manifestations - the container runtime can't reap a
process that won't exit, and no amount of re-issuing the delete command
at the orchestration layer changes what's happening several layers down
in the kernel. The fix is always the same shape: find and resolve the
actual I/O the process is blocked on, then let the already-queued signal
land on its own.

## Go deeper

- **Book:** *Systems Performance* — Brendan Gregg — direct coverage of
  process states, blocked I/O, and diagnosing what a process is actually
  waiting on rather than assuming it's "just slow."
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man1/ps.1.html
  and https://man7.org/linux/man-pages/man2/signal.2.html — document the
  `ps` `STAT` column values and exactly when signal delivery happens
  relative to a blocked syscall.
- **Website:** Brendan Gregg's site — https://www.brendangregg.com — the
  broader methodology of diagnosing *what a process is blocked on*
  before deciding a restart, a kill, or a reboot is the right next step.
- **Book:** *Site Reliability Engineering* — Google, ed. Betsy Beyer et
  al. (free at https://sre.google/books/) — see the chapters on
  effective troubleshooting, particularly the discipline of not
  repeating an ineffective mitigation (like a third restart) once it's
  demonstrated not to work.
