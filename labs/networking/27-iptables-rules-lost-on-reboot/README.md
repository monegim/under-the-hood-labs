# Lab 27 — iptables Rules Lost on Reboot

## Objective
Set a real, working firewall rule live, watch it vanish the moment the
kernel's netfilter tables reset, and fix it so it actually survives —
not just reappears once, by hand, again.

## Why this matters
`iptables -A`/`-I`/`-D` all operate purely on the kernel's in-memory
netfilter tables. Nothing about running those commands writes anything
to disk. On a fresh boot, the kernel starts with empty tables — no
memory of what was configured last time — and stays empty unless
something explicit loads a saved ruleset during startup. This is
completely by design, and it's exactly why "I set the firewall rule and
confirmed it works" is not the same claim as "the firewall rule will
still be there after the next reboot" — a huge number of real
"we thought we were protected" incidents are precisely this gap.

## Prerequisites
- A Linux VM, `sudo` access, `iptables`, `netcat-openbsd`

Check first:
```bash
which iptables nc
systemctl is-enabled netfilter-persistent 2>&1 || echo "not installed/enabled yet"
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This starts a listener on port 9999, then applies a real, live
`iptables` rule blocking it — and confirms the block actually works.
`netfilter-persistent` is deliberately not installed yet.

## Step 2 — Confirm it's genuinely working right now
```bash
echo hi | nc -w2 127.0.0.1 9999; echo "exit: $?"
```
Should fail/time out — the rule is live.

## Step 3 — Simulate a reboot, honestly
A literal reboot isn't required to reproduce this — what actually
matters is what the kernel's netfilter tables look like at the next
boot, which is exactly what a full flush reproduces:
```bash
sudo iptables -F
sudo iptables -L INPUT -n -v
```
Empty. This is genuinely what `INPUT` would look like after a real
reboot with nothing configured to reload it.

## Step 4 — Confirm the gap
```bash
echo hi | nc -w2 127.0.0.1 9999; echo "exit: $?"
```
Now it succeeds — the block is gone.

## Step 5 — Fix it properly (not just reapply the rule)
```bash
sudo iptables -A INPUT -p tcp --dport 9999 -j DROP
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive sudo apt-get install -y -qq iptables-persistent
```
(The `iptables-persistent` package install prompts to save current
rules on first install — accept, or run the save step explicitly:)
```bash
sudo netfilter-persistent save
sudo systemctl enable netfilter-persistent
```

## Step 6 — Verify both halves of the fix
```bash
echo hi | nc -w2 127.0.0.1 9999; echo "exit: $?"
cat /etc/iptables/rules.v4 | grep 9999
systemctl is-enabled netfilter-persistent
```
The rule needs to be true on all three counts — live now, saved to the
file the loader actually reads, and that loader actually enabled to run
at boot — for this to genuinely survive a real reboot.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — backed up, but never wired up to load:**
```bash
sudo iptables -F
sudo iptables -A INPUT -p tcp --dport 9999 -j DROP
sudo iptables-save > /etc/iptables/rules.v4
echo hi | nc -w2 127.0.0.1 9999; echo "exit: $?"
```
The rule is live, and it's genuinely saved to the exact file
`netfilter-persistent` expects. Simulate a reboot again
(`sudo iptables -F`) and check whether it comes back on its own —
without manually re-running anything:
```bash
sudo iptables -F
sudo systemctl restart netfilter-persistent 2>&1 || echo "netfilter-persistent: $?"
sudo iptables -L INPUT -n
```
Figure out exactly what's still missing, given the rules file itself is
correct and in the right place.

**Challenge B — saved to the wrong place entirely:**
```bash
sudo iptables -F
sudo iptables -A INPUT -p tcp --dport 9999 -j DROP
sudo iptables-save > /root/my-firewall-backup.txt
sudo iptables -F
sudo systemctl restart netfilter-persistent 2>&1 || true
sudo iptables -L INPUT -n
```
A real backup file exists, with the correct rule in it, sitting right
there on disk — and the rule still doesn't come back automatically.
Compare the path used here to Step 6's — what does
`netfilter-persistent` actually load rules from, and how would you have
found that out *before* discovering it the hard way?

See `solution.md` only after you've formed your own diagnosis.
