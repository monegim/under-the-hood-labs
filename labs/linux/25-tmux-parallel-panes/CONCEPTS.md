# Lab 25 — Concept: Panes, Windows, and Synchronized Input

## What's actually going on

A tmux **session** can contain multiple **windows** (think: tabs), and
each window can be split into multiple **panes** — each pane is its own
independent pseudo-terminal, running its own shell (or whatever command
you launched it with), with its own working directory, its own
scrollback, its own process tree. Splitting (`Ctrl-b %` / `Ctrl-b "`)
doesn't share any state between panes by default — they're genuinely
separate terminals that happen to be tiled on screen together, which is
exactly why Step 3's `cat version.txt` had to be run three separate
times, once per pane, to see three separate results.

`synchronize-panes` changes that, but only for *input*. When it's on,
tmux takes every keystroke sent to the currently active pane and
replicates it verbatim to every other pane in the same window — each
pane's shell then interprets and executes that same keystroke sequence
independently, against its own state (its own working directory, its
own files, its own environment). This is exactly why Step 4's `pwd`
demonstration shows three *different* outputs despite being triggered
by one set of keystrokes: sync duplicates the input, not the output —
each pane is still a fully separate process doing its own thing with
identical instructions. It's the tmux equivalent of a "type once, apply
everywhere" macro across N independent terminals, and it has no
built-in concept of "this specific command is read-only, safe to
broadcast" versus "this one mutates state, be careful" — from tmux's
point of view, `cat version.txt` and `rm -rf /` are exactly the same
kind of thing: a byte sequence to replicate to every pane.

There is genuinely no reliable passive signal in a default tmux
configuration that a session has synchronized panes turned on — no
color change, no automatic status-bar warning, unless you've
specifically configured one (many experienced tmux users do exactly
that, binding `pane-border-style`/`pane-active-border-style` to change
color when `#{pane_synchronized}` is true, precisely because this
failure mode is common enough to be worth defending against explicitly
in configuration, not just in habit).

## Where this shows up in the real world

Synchronized panes (and its close cousins — `pssh`/`clusterssh`/`csshx`,
Ansible ad-hoc commands, any "run this on every host in the fleet at
once" tool) are genuinely valuable for exactly the class of task this
lab demonstrates: comparing config or state across a fleet quickly, or
applying an identical, deliberately-fleet-wide change. The failure mode
is equally well known across all of these tools, not unique to tmux — a
command intended for one target, issued while a broadcast mechanism is
still active, reaching hosts it was never meant to touch is a
recurring, real category of self-inflicted incident. It's common enough
that many teams' runbooks explicitly call out "confirm you are targeting
what you think you're targeting" as its own checklist item before any
command capable of changing state, independent of which specific
broadcast tool is in use.

## Go deeper

- **Website/docs:** tmux official wiki — https://github.com/tmux/tmux/wiki — canonical reference for panes, windows, sessions, and `synchronize-panes`.
- **Website/docs:** tmux man page — https://man7.org/linux/man-pages/man1/tmux.1.html — the authoritative reference for every `tmux`/`setw` option and format variable, including `#{pane_synchronized}`.
- **Book:** *tmux 2: Productive Mouse-Free Development* — Brian P. Hogan (Pragmatic Bookshelf) — a full practical guide to tmux workflows, panes, and configuration.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — practical tmux usage content alongside broader Linux administration material.
