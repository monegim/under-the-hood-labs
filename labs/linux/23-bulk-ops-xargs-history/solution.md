# Lab 23 — Solutions

## Challenge A — a filename with a space breaks naive xargs

**Check:**
```bash
ls -la /var/tmp/lab23-cache/dir999/
```
`file3.tmp` is gone, but `file 1.tmp` and `file 2.tmp` are both still
there — and the `rm` command almost certainly printed something like
`rm: cannot remove 'file': No such file or directory` and the same for
`1.tmp`, `file`, `2.tmp`.

**Diagnosis:** `xargs`'s default behavior splits its input on
whitespace *and* newlines — it has no idea that a single space inside
`file 1.tmp` is part of one filename rather than a separator between
two arguments. `find ... -name '*.tmp'` piped straight into `xargs rm`
(no `-print0`/`-0`) turns the one path `/var/tmp/lab23-cache/dir999/file
1.tmp` into two separate arguments, `.../file` and `1.tmp` — neither of
which exists — while leaving the real file untouched. This is silent
data corruption of your command's *input*, not a crash: `rm` runs, some
of it "succeeds" (on garbage paths that don't exist, so it just errors
per-path and moves on), and the actual target survives by accident.

**Fix:**
```bash
find /var/tmp/lab23-cache/dir999 -name '*.tmp' -print0 | xargs -0 rm
```
`-print0` makes `find` separate paths with a null byte (`\0`) instead of
a newline, and `xargs -0` tells `xargs` to split its input on null bytes
instead of whitespace/newlines. A null byte can't legally appear inside
a Unix filename, so this is the only delimiter that's guaranteed safe
for every possible filename — including ones with spaces, tabs, or even
literal newlines in them.

**Lesson:** never pipe `find` into plain `xargs` (or `for f in $(find
...)`) in scripts or automation you don't fully control the filenames
for — `-print0`/`-0` isn't a style preference, it's the difference
between "always correct" and "correct until someone's filename has a
space in it," and you often don't get to choose what filenames show up
on a real system (user uploads, generated report names, other people's
tooling).

---

## Challenge B — a loose pattern kills more than intended

**Check:**
```bash
pgrep -fl worker
```
Only `worker-1.sh` shows up (if it was even still running when you
checked) — `network-worker-monitor.sh` is gone.

**Diagnosis:** `pgrep -f worker` matches the pattern `worker` anywhere
in the full command line (that's what `-f` means — match against the
whole command, not just the process name) of *every* process on the
box. Both `/var/tmp/lab23-workers/worker-1.sh` and
`/var/tmp/lab23-important/network-worker-monitor.sh` contain the
substring `worker`, so both matched, and `xargs kill` — which has no
concept of "intended target" versus "coincidental match" — killed
whatever `pgrep` handed it, no confirmation, no distinction.
`kill`/`xargs kill` is exactly as precise as the pattern feeding it, and
substring matching on process names is almost never precise enough on a
box with more than a handful of processes.

**Fix:** restart the important process, then redo the cleanup with a
pattern that can only match the intended targets — the actual path
prefix, not a loose keyword:
```bash
bash /var/tmp/lab23-important/network-worker-monitor.sh &
disown
pgrep -f "/var/tmp/lab23-workers/worker-" | xargs kill
```

**Lesson:** `pgrep -f <pattern> | xargs kill` is genuinely dangerous the
moment the pattern isn't specific enough, precisely because it's fast
and requires no per-target confirmation — the same property that makes
bulk operations powerful makes a bad pattern powerful too. Before piping
`pgrep`/`find`/anything into `xargs kill` or `xargs rm`, run the *first*
half alone and actually read the output — `pgrep -fl worker` before
`pgrep -f worker | xargs kill`, always, no exceptions, especially on a
shared box where you don't personally know every running process.
