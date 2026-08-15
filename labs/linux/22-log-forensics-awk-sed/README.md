# Lab 22 — Log Forensics with awk/sed

## Objective
Find which client is actually responsible for a load spike across
75,000 lines of rotated access logs — using `awk`/`sed`/`sort`/`uniq`,
not by scrolling through files — then block it.

## Why this matters
When your log aggregation tool is down, slow, or just doesn't have the
one specific query you need right now, `awk`/`sed`/`grep` on the raw
files is the fallback that always works. It's also often *faster* than
waiting on a dashboard to load a query against a big index — a
well-aimed one-liner across a few hundred thousand lines runs in
seconds. The skill isn't memorizing awk syntax, it's knowing which
one-liner answers which question, and — just as important — knowing
when your first answer is wrong because of something in the data you
didn't account for.

## Prerequisites
- A Linux VM, `sudo` access (to add an iptables rule)
- `python3` (used only to generate the synthetic logs)

Check first:
```bash
python3 --version
sudo iptables -L INPUT -n
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This writes `access.log.1` through `access.log.5` to `/var/tmp/lab22-logs/`
(75,000 lines total, ~15,000 per file, spanning a 2-hour window). The
on-call channel says: *"app server under heavy load, check access
logs."* No other hint.

## Step 2 — Get a sense of scale
```bash
wc -l /var/tmp/lab22-logs/access.log.*
cat /var/tmp/lab22-logs/access.log.* | wc -l
```
75,000 lines is too many to read. You need aggregation, not inspection.

## Step 3 — Find the top client by request count
```bash
cat /var/tmp/lab22-logs/access.log.* \
  | awk '{print $1}' \
  | sort | uniq -c | sort -rn | head -10
```
One IP should stand out by a wide margin over everyone else — not a
close second place, an obvious outlier.

## Step 4 — Confirm what it's actually doing
```bash
awk -v ip="<the IP from step 3>" '$1==ip {print $4}' /var/tmp/lab22-logs/access.log.* \
  | sort | uniq -c
```
(Log format is `IP TIMESTAMP METHOD PATH STATUS SIZE` — `$4` is the
path.) Confirm it's hammering one specific endpoint, not spread across
normal traffic.

## Step 5 — Block it
```bash
sudo iptables -A INPUT -s <the IP> -j DROP
```

## Step 6 — Verify
```bash
sudo iptables -L INPUT -n | grep <the IP>
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a file that doesn't match the others:**
```bash
sed -i 's/^/EDGE-7 /' /var/tmp/lab22-logs/access.log.3
```
Re-run Step 3's exact one-liner. Something in the output looks wrong —
a value that clearly isn't an IP address, showing up with a suspiciously
high count. Before trusting any aggregate number again, check each file
individually:
```bash
for f in /var/tmp/lab22-logs/access.log.*; do
  echo "== $f =="
  awk '{print $1}' "$f" | sort | uniq -c | sort -rn | head -3
done
```
Figure out what happened to file 3, and why it would make a
naively-combined count across all 5 files unreliable — even in cases
where, like this one, the final answer doesn't actually change.

**Challenge B — the historical top offender isn't today's problem:**
```bash
python3 - <<'PYEOF'
import random
random.seed(99)
lines = []
for i in range(3000):
    minute = int((i / 3000) * 6)
    second = i % 60
    lines.append(f"203.0.113.200 2026-08-10T15:{minute:02d}:{second:02d}Z GET /api/checkout 200 500")
with open("/var/tmp/lab22-logs/access.log.6", "w") as f:
    f.write("\n".join(lines) + "\n")
print("appended a burst to access.log.6")
PYEOF
```
Re-run Step 3's exact one-liner against all 6 files now. The same IP
from before still wins by total volume — but that's stale. A fresh
burst just landed. Figure out how to filter to a *recent time window*
before aggregating (the timestamps are ISO 8601, so they sort correctly
as plain strings — no date-parsing library needed), find out who's
actually spiking right now, and block that one instead.

See `solution.md` only after you've formed your own diagnosis.
