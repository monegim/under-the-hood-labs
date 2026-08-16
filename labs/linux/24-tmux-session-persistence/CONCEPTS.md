# Lab 24 — Concept: tmux, Sessions, and Why SIGHUP Kills Foreground Jobs

## What's actually going on

Every process has exactly one parent, fixed at the moment it's created
(`fork()`), and every process belongs to a session and a process group —
bookkeeping the kernel uses to know which terminal, if any, a process is
attached to and which processes should receive job-control signals
together. When a terminal (a real one, or the pseudo-terminal an SSH
connection allocates) goes away — the connection drops, the emulator
window closes — the kernel delivers `SIGHUP` ("hangup") to the processes
that were attached to it. `SIGHUP`'s default disposition, for a process
that hasn't explicitly told the kernel otherwise, is to terminate
immediately. This isn't a bug or a Linux quirk — it's the deliberate,
decades-old mechanism by which "the thing you were talking to over this
terminal just went away" gets communicated to whatever was running
there, and it's exactly what this lab's `kill -HUP` is standing in for.

`nohup` works by changing exactly that one thing: it starts the process
with `SIGHUP` explicitly set to be ignored (`SIG_IGN`), so the signal
still arrives, but the process's disposition for it is "do nothing"
instead of "terminate." That's real, narrow, effective protection
against this one failure mode — and nothing more. It doesn't give the
process a persistent terminal to reconnect to; its stdin/stdout/stderr
are just redirected (to `nohup.out` by default, or wherever you send
them), which is why a `nohup`'d job is fine for a script that just needs
to keep running, but useless for anything you need to interact with
later.

tmux solves a related but larger problem differently: instead of making
a single process immune to one specific signal, it interposes an entire
extra layer — a `tmux` **server**, a background daemon that owns real
pseudo-terminals of its own, one per pane. When you run a command inside
a tmux session, that command's actual parent (and the terminal it's
attached to) belongs to the tmux server, not to your SSH session's
shell. Your SSH connection dropping affects the tmux **client** you were
using to view that server — the client goes away, but the server, and
everything running inside its panes, doesn't notice, because it was
never in the client's process tree or attached to the client's terminal
to begin with. "Detaching" (`Ctrl-b d`) and "your connection dying while
attached" look almost identical from the server's point of view — in
both cases, a client stops talking to it, and the server just keeps
going, with the same panes, same scrollback, same running processes,
waiting for a client (the same one reconnecting, or a different one) to
attach again.

This is also exactly why Challenge B doesn't work: a tmux session
created after a process already exists has no way to reach back and
change that process's parent, session, or controlling terminal — none
of those are things you can reassign after the fact. Protection has to
be structural, decided at the moment a process starts, not applied
retroactively by something that merely happens to exist elsewhere on
the same machine at the same time.

## Where this shows up in the real world

Losing a long-running job to a dropped SSH connection is one of the most
common, most avoidable operational annoyances there is, and it's
specifically painful during incidents — the exact moment a connection is
most likely to be unstable (you're stressed, moving between networks,
maybe on a spotty VPN) is also the moment you're most likely to be
running something you can't afford to lose. Runbooks for long
migrations, big data transfers, and multi-step remediation scripts
routinely start with "run this inside tmux/screen" as a first line, not
a nice-to-have — and post-incident reviews not infrequently include "we
lost 20 minutes because the fix was running in a plain SSH session and
the VPN blipped" as a contributing factor worth fixing process around,
not just a bad-luck footnote.

## Go deeper

- **Website/docs:** tmux official wiki — https://github.com/tmux/tmux/wiki — the canonical reference for tmux commands, session/window/pane concepts, and configuration.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man7/signal.7.html — canonical reference for `SIGHUP` and default signal dispositions.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man1/nohup.1p.html — the `nohup` POSIX specification.
- **Book:** *The Linux Programming Interface* — Michael Kerrisk — covers sessions, process groups, controlling terminals, and signal disposition in full technical depth; the exact mechanisms this lab demonstrates hands-on.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — has practical tmux/screen usage content alongside its broader Linux administration material.
