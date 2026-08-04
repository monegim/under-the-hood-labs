# Lab 18 — Concept: Reading Syscalls and Library Calls Instead of Guessing

## What's actually going on

Every program eventually has to ask the kernel to do something on its
behalf - open a file, read bytes, wait on a timer, fork a process - and
each of those requests is a syscall. `strace` works by attaching to a
process via `ptrace(2)` and intercepting every syscall it makes, printing
the syscall name, its arguments (with file descriptors, paths, and flags
decoded into readable form), and its return value - including, critically,
`errno` when it fails. This lab's main incident is a single line of proof:
`openat(AT_FDCWD, "config.ini", O_RDONLY) = -1 ENOENT`. No application log
message told you the app was resolving a relative path against `/`
instead of `/opt/configapp` - the log just said "could not read config
file," which is technically true and practically useless. The syscall
trace can't be vague like that; it shows the exact path string the kernel
was asked to resolve and exactly why that resolution failed, which is
precisely the gap between "something is wrong" and "here is what is
wrong and here is the fix."

`ltrace` intercepts a different layer: library calls, most commonly
against libc (`getenv`, `fopen`, `strcmp`, `malloc`, and so on). This
matters because not every bug lives at the syscall boundary. Challenge A's
`getenv("CONFIGAPP_TOKEN")` returning `NULL` isn't a failed syscall at
all - reading a process's already-inherited environment table doesn't
touch the kernel once the process has started, so `strace` has nothing to
show you here. `ltrace` does, because it's watching the library call
itself, not what that library call does or doesn't ask the kernel to do.
The practical rule of thumb: if the bug is "a syscall failed" (a file
that isn't where it's expected, a socket connect that's refused, a signal
that isn't being delivered), reach for `strace`. If the bug is "a library
function behaved unexpectedly given its inputs" (an environment variable
that should have been set, a string comparison that should have matched),
reach for `ltrace`. Real debugging often needs both, in sequence, exactly
like this lab's two challenges.

Challenge B is a variation on the strace half that's worth separating out
on its own, because it breaks the assumption most people bring to
`ps`/`top`: that a process's state (`R`, `S`, `D`, `Z`) plus its "active"
status from systemd tells you whether something is wrong. It doesn't. A
process correctly, patiently blocked in `read()` on a pipe with no data
coming is in a completely normal `S` (interruptible sleep) state, and
`systemctl status` reports it as `active (running)` because, from
systemd's point of view, nothing has crashed or exited - the process is
doing exactly what its code told it to do. The only tool in this lab that
can tell you *which* syscall a live, healthy-looking process is currently
parked in is `strace -p <pid>` - attaching to an already-running process
rather than launching a fresh one under trace. This is a different mode of
the same tool: `strace -f <command>` for something you can launch fresh
and watch from the start (useful for a fast-failing, restart-looping
service where reconstructing the exact invocation and running it manually
sidesteps the timing problem of trying to catch a one-shot failure with
`-p`), versus `strace -p <pid>` for a long-lived process you need to
observe live, right now, exactly as it's running in production.

## Where this shows up in the real world

"It fails and the log doesn't say why" is one of the most common shapes
an on-call page takes, and a working-directory or path-resolution
assumption baked into a unit file, a Docker `ENTRYPOINT`, a cron job, or a
CI runner is one of the most common root causes - it's invisible in local
development (you always run it from the right directory by habit) and
only surfaces the moment something else launches the same binary with a
different `cwd`. The `ltrace` scenario - "works when I run it myself,
fails under systemd/cron" - is exactly as common, and for the same
underlying reason: your interactive shell's environment is not what a
service manager or scheduler gives the processes it launches. And the
"looks healthy but is hung" pattern is the reason experienced engineers
treat "the process is up" and "the process is doing its job" as two
separate claims that need two separate kinds of evidence - `ps`/
`systemctl status` for the first, and `strace -p` (or an application-level
liveness/heartbeat check) for the second.

## Go deeper

- **Book:** *The Linux Programming Interface* — Michael Kerrisk — covers
  the syscall/library-call boundary this lab is built on, and the
  semantics of `open()`, environment inheritance, and pipes/FIFOs in
  detail.
- **Book:** *Systems Performance* — Brendan Gregg — has direct coverage of
  tracing tools (including `strace` and its overhead characteristics) as
  part of a general methodology for diagnosing "what is this process
  actually doing right now."
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man1/strace.1.html
  — canonical `strace(1)` reference, including `-p`, `-f`, and `-e trace=`.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man7/fifo.7.html
  and https://man7.org/linux/man-pages/man2/open.2.html — exact semantics
  of FIFO open()/read() blocking behavior and `AT_FDCWD` path resolution.
- **Website/docs:** Arch Linux Wiki — https://wiki.archlinux.org — has
  practical, precise pages on systemd unit environment handling
  (`EnvironmentFile=`, `WorkingDirectory=`) referenced by this lab's fixes.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV —
  covers systemd unit fundamentals relevant to both of this lab's
  services.
