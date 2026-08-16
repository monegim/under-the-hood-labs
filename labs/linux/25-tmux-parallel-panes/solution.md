# Lab 25 — Solutions

## Challenge A — the fix that went everywhere

**Check:**
```bash
cat /var/tmp/lab25/host1/restart.log
cat /var/tmp/lab25/host3/restart.log
```
Both have a `restarted ...` line — hosts that were never broken now
show a restart event that genuinely never should have happened, right
alongside host2's legitimate one.

**Diagnosis:** `synchronize-panes` was still on from Step 4, and it
doesn't turn itself off — it stays on until something explicitly turns
it off, with no visual difference in a plain terminal to remind you it's
active (some tmux configs add a status-bar indicator or colored pane
borders when sync is on; the default configuration does not). Every
keystroke typed into Step 6's fix — `echo "v2.3.1" > version.txt` and
the `restart.log` append — went to whichever pane had focus *and every
other pane at the same time*, each executing it against its own
`version.txt`/`restart.log` in its own directory. On real infrastructure,
this isn't a cosmetic file-content mismatch — it's the same command
that restarted the broken host also restarting two healthy ones, at the
same moment, for no reason.

**Fix:** clean up the damage (in this lab, that's just resetting), and
build the actual fix: **always run `display-message
"synchronized: #{pane_synchronized}"` (or check for a visual sync
indicator, if your config has one) immediately before typing any
command that changes state** — not just once at the start of a session,
every time, because sync state can be toggled at any point and there's
no reliable way to recall "did I turn it off" from memory alone once
you're a few steps into an investigation.

**Lesson:** a tool that makes broadcasting safe and fast (one keystroke
reaches every pane) is, by the same mechanism, a tool that makes an
accidental broadcast just as fast. The fix isn't "don't use
synchronize-panes" — it's "treat turning it off as part of the sequence
every single time, verified, not assumed."

---

## Challenge B — same trap, harder to notice

**Check:**
```
Ctrl-b :
display-message "synchronized: #{pane_synchronized}"
```

**Diagnosis:** the exercise here isn't the command itself — you already
know it from Step 5 — it's building the habit of running it *before*
acting, specifically at the moment your certainty is lowest (after a
distraction, mid-incident, several steps into a longer sequence), rather
than only running it once near the start of a session and trusting your
memory afterward. Sync state is exactly the kind of thing that's
invisible until you check it and expensive to get wrong, which makes it
a bad candidate for "I'm pretty sure I turned that off."

**Fix:** whatever `#{pane_synchronized}` reports, act on the actual
value — turn it off explicitly (`setw synchronize-panes off`) if it
shows `1`, regardless of whether you *think* you already did, before
typing anything that changes state.

**Lesson:** the real defense against Challenge A isn't "remember to turn
sync off" — memory is exactly what fails under incident pressure or
after a distraction. The defense is making the check itself cheap and
routine enough (one command, run as a reflex, not a special
circumstance) that it doesn't depend on remembering anything at all.
