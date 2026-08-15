# Lab 22 — Solutions

## Challenge A — a file that doesn't match the others

**Check:**
```bash
for f in /var/tmp/lab22-logs/access.log.*; do
  echo "== $f =="
  awk '{print $1}' "$f" | sort | uniq -c | sort -rn | head -3
done
```
Files 1, 2, 4, 5 show `203.0.113.77` as the clear top entry, each around
4,400-4,500 occurrences. File 3 shows a single "IP" — `EDGE-7` — with a
count of 15,000: every line in that file, no exceptions.

**Diagnosis:** `sed -i 's/^/EDGE-7 /'` prepended a token to the start of
every line in `access.log.3`. Since `awk`'s default field splitting is
plain whitespace with no concept of "this file's format is different,"
`$1` in that file is now the literal string `EDGE-7`, not an IP — the
real IP got pushed to `$2`. Combined across all 5 files, the naive
`awk '{print $1}' access.log.* | sort | uniq -c` still happens to rank
`203.0.113.77` above `EDGE-7` here (≈17,900 vs 15,000 — the other 4
files' worth is still enough to win), but that's closer than it should
be, and it's luck, not correctness — a smaller noisy-IP share, or one
more reformatted file, and the naive combined count would give the
wrong top entry outright.

**Fix:** don't trust a combined multi-file aggregate until you've
sanity-checked that every file actually has the same shape:
```bash
awk '{print $1}' /var/tmp/lab22-logs/access.log.3 | grep -c '^[0-9]'
```
A near-zero count (versus 15,000 total lines) is the tell that `$1`
isn't IPs in this file. Extract correctly for the odd file specifically
(`$2` instead of `$1`), or normalize it back (`sed -i 's/^EDGE-7 //'
access.log.3`) before aggregating.

**Lesson:** a multi-file `awk '{print $1}' *.log` pipeline silently
assumes every file has identical structure. It will not error out if
that's false — it will just quietly produce a number, and a number that
happens to still be directionally right is exactly the kind of thing
that makes you stop checking. Spot-check per-file before trusting a
combined aggregate, especially across files from different log sources
(load balancers, different app versions, different upstreams).

---

## Challenge B — the historical top offender isn't today's problem

**Check:**
```bash
MAX_TS=$(cat /var/tmp/lab22-logs/access.log.* | awk '{print $2}' | sort | tail -1)
CUTOFF=$(python3 -c "
from datetime import datetime, timedelta
ts = datetime.strptime('$MAX_TS', '%Y-%m-%dT%H:%M:%SZ')
print((ts - timedelta(minutes=10)).strftime('%Y-%m-%dT%H:%M:%SZ'))
")
cat /var/tmp/lab22-logs/access.log.* \
  | awk -v cutoff="$CUTOFF" '$2 >= cutoff {print $1}' \
  | sort | uniq -c | sort -rn | head -5
```
Filtered to just the last 10 minutes of log data, `203.0.113.200` is
now the clear top entry — not `203.0.113.77`, which was winning the
*unfiltered* Step 3 count purely on accumulated historical volume.

**Diagnosis:** `203.0.113.77`'s 30% share was spread evenly across the
whole 2-hour window — real, but not new, not urgent, and (per the
earlier steps) already blocked. `203.0.113.200` just started a
concentrated 3,000-request burst against `/api/checkout` in the last 6
minutes of log data. Total-volume-since-the-beginning-of-the-log and
volume-right-now are different questions, and re-running the exact same
unfiltered one-liner from Step 3 answers the first one when the page is
actually asking the second.

**Fix:**
```bash
sudo iptables -A INPUT -s 203.0.113.200 -j DROP
```

**Lesson:** ISO 8601 timestamps sort correctly as plain strings
(`"2026-08-10T14:55:00Z" < "2026-08-10T15:00:00Z"` is true using pure
lexicographic comparison), which is exactly why `awk -v cutoff=... '$2
>= cutoff'` works with no date-parsing at all — that's worth knowing on
its own. But the bigger lesson is about the question, not the syntax:
"who's using the most resources" and "who's using the most resources
*right now*" are different questions with potentially different
answers, and a rolling incident needs the second one. Always know
whether your aggregate is windowed or cumulative before you trust it.
