# Lab 24 — Solutions

## Challenge A — is tmux really required, or would `nohup` have worked?

**Check:**
```bash
cat /var/tmp/lab24/DONE
```
It's there — the `nohup`'d job survived the exact same `kill -HUP` that
killed the plain background job in Step 2.

**Diagnosis:** `nohup` genuinely does one specific thing: it makes the
process ignore `SIGHUP` (technically, `SIG_IGN` for that signal specifically,
so the process doesn't even see it as an event). That's real protection
against exactly the failure Step 2 demonstrated, and it's much simpler
than tmux — one command prefix, no server process, nothing to install.
So `nohup`/`disown` are legitimate, older tools for this exact problem,
and this lab isn't claiming tmux is the only way to survive a dropped
connection.

What `nohup` doesn't give you: a terminal to come back to. A `nohup`'d
job's stdout/stderr go to a file (or wherever you redirected them) — you
can `tail -f` that file, but you can't attach an interactive terminal to
the running process. If the job were something interactive — a `mysql`
shell you're debugging in, a `top` you want to keep glancing at, a `vim`
session, a Python REPL you're mid-investigation in — `nohup` gives you
no way back into it at all. tmux gives you a full virtual terminal that
persists independently and that you can reattach to and interact with
exactly as if you'd never left, at the cost of an actual server process
to manage. They solve overlapping but different problems:
"don't let SIGHUP kill this" (`nohup`) vs. "let me walk away from and
back into a live, interactive session" (tmux).

**Lesson:** don't reach for tmux out of habit when `nohup`/`disown`
would do — but recognize the specific thing tmux adds that neither of
them can: a persistent, reattachable *terminal*, not just signal
immunity for a background process.

---

## Challenge B — tmux can't retroactively protect a job that's already running

**Check:**
```bash
cat /var/tmp/lab24/DONE 2>/dev/null || echo "no DONE marker"
```
No marker — the job died exactly like Step 2's, despite a tmux session
existing by the time the `SIGHUP` was sent.

**Diagnosis:** creating `toolate` with `tmux new-session -d -s toolate`
starts a brand new, empty session — it has no relationship whatsoever to
the `job.sh` process that was already running as a plain background job
of your shell before that command was ever typed. A process's parent is
fixed at the moment it's created (`fork()`/`exec()`); nothing you run
afterward can reach back and change who a process's parent is, or move
it into a different session's process tree. `job.sh` was, and remained,
a child of your interactive shell the entire time — the existence of an
unrelated tmux session elsewhere on the box changes nothing about that.

**Fix:** there isn't one after the fact — the job would need to be
killed and restarted correctly:
```bash
tmux new-session -d -s labjob-retry '/var/tmp/lab24/job.sh'
```
The general recovery move, if you realize mid-job that you should have
started it differently: let it finish (if it's close), or accept the
risk and restart it the right way, rather than assuming any wrapping
you do now protects a process that's already running.

**Lesson:** tmux (like `nohup`) has to wrap a process *at the moment you
start it* — there is no "adopt an already-running orphan into
protection" move. This is exactly why the instinct worth building is
"is this going to take a while — start it in tmux from the start,"
not "start it plainly and switch to tmux later if it seems slow,"
because by the time it seems slow, the window to protect it has already
closed.
