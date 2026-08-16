# Lab 25 — Parallel Monitoring and the Synchronize-Panes Trap

## Objective
Use split tmux panes to compare three "hosts" side by side, find the
one that's drifted, and fix *only* that one — while `synchronize-panes`
sits right there, one keystroke away from fixing (or breaking) all
three at once.

## Why this matters
Tabbing between separate terminal windows to compare several hosts
loses context — by the time you've checked host 3, you've forgotten
exactly what host 1 showed. Split panes fix that: everything's visible
at once. tmux also has `synchronize-panes`, which broadcasts every
keystroke you type into one pane to *all* panes simultaneously — genuinely
useful for running the same read-only check across a fleet in one
motion, and genuinely dangerous the moment you forget it's still on and
type something meant for just one host. This lab is really about that
second half: the tool that makes fleet-wide checks fast is the same
tool that turns "restart the one broken host" into "restart all three,"
silently, if you're not paying attention to what's currently active.

## Prerequisites
- A Linux VM, `sudo` access (only if `tmux` isn't already installed)
- This lab is done interactively at the keyboard — the commands below
  are things you type inside tmux, not a script that does it for you.

Check first:
```bash
tmux -V || echo "not installed yet — setup.sh will install it"
```

## Step 1 — Build the scenario
```bash
chmod +x setup.sh
./setup.sh
```
This creates `/var/tmp/lab25/host1/`, `host2/`, `host3/` — each with a
`version.txt` and an empty `restart.log`. One of the three has quietly
drifted to an older version. Nothing tells you which one yet.

## Step 2 — Split into three panes
Start (or attach to) a tmux session, then split it into three panes
side by side:
```
tmux new-session -s lab25
```
Inside tmux:
- `Ctrl-b %` splits vertically (side by side)
- `Ctrl-b "` splits horizontally (stacked)
- `Ctrl-b <arrow key>` moves focus between panes

Build whatever three-pane layout you're comfortable with, then `cd` each
pane into a different host directory: `cd /var/tmp/lab25/host1`,
`.../host2`, `.../host3`.

## Step 3 — Compare, without synchronizing
In each pane individually (sync is off by default), run:
```bash
cat version.txt
```
Read all three outputs side by side. One of them doesn't match the
other two.

## Step 4 — Confirm it the fleet-wide way
Turn on synchronized panes and run one command that fans out to all
three at once:
```
Ctrl-b :
setw synchronize-panes on
```
(Or from a shell, in any one pane: `tmux setw synchronize-panes on`.)
Now anything you type appears in *every* pane. Try:
```bash
pwd
```
All three panes show their own (different) path — proof the same
keystrokes really did run independently in each one, not just visually
mirror one pane.

## Step 5 — Turn sync back off before you fix anything
```
Ctrl-b :
setw synchronize-panes off
```
This is the step that matters most in this whole lab. Confirm it
actually took effect before typing anything further:
```
Ctrl-b :
display-message "synchronized: #{pane_synchronized}"
```
Should show `0`.

## Step 6 — Fix only the drifted host
Move focus (`Ctrl-b <arrow>`) into the pane that's `cd`'d into the
drifted host's directory specifically, and only there:
```bash
echo "v2.3.1" > version.txt
echo "restarted $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> restart.log
```

## Step 7 — Verify
In each pane individually:
```bash
cat version.txt
cat restart.log
```
The drifted host now matches the other two, and only its `restart.log`
has an entry — the other two are untouched.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the fix that went everywhere:**
```bash
./reset.sh
```
Redo Steps 2-4 (split panes, compare, turn sync on to confirm the
drift) — but this time, skip Step 5 entirely and go straight from
Step 4 into Step 6's fix commands while sync is still on. Then check
all three hosts:
```bash
cat /var/tmp/lab25/host1/restart.log
cat /var/tmp/lab25/host2/restart.log
cat /var/tmp/lab25/host3/restart.log
```
Something's in files that should still be empty. Explain exactly what
happened, why nothing on screen warned you at the moment you typed the
fix, and what you'd check *before* typing a state-changing command into
any pane, every time, as a habit rather than a one-off catch.

**Challenge B — same trap, harder to notice:**
```bash
./reset.sh
```
This time, split into panes, turn sync on to compare all three
`version.txt` files at once (Step 4's move), then get distracted for a
moment — check something else, glance away, whatever a real incident
actually feels like — and come back to fix the drifted host. Before you
type anything, run only the display-message check from Step 5 (don't
turn sync off yet, just check its current state). What does it show,
and if you can't remember whether you turned it off already, what's the
one command that tells you for certain, instead of guessing from
memory?

See `solution.md` only after you've formed your own diagnosis.
