# Level 6 — Production Incidents

Everything before this level taught you one mechanism at a time: an
inode-exhaustion gotcha, a blocked-ICMP PMTUD blackhole, a stuck D-state
process, replication lag from disk contention. Real incidents rarely
announce which of those you're looking at. This level drops you into a
realistic on-call page - symptoms only, no hint which subsystem is at
fault - and combines two or more mechanisms from Levels 1-5 into a
single synthetic incident.

> Incident #12: Latency increased from 8ms to 1.2s. Error rate is 12%.
> CPU is only 25%. Memory looks normal. Customers cannot log in.
> Find the root cause. No hints. Just logs, metrics, and a broken
> environment.

## Format

Each incident is different from the rest of the repo in one important
way: there's no numbered "Step 1, Step 2" build-it-yourself walkthrough.
Instead:

- **The page** - the incident exactly as an on-call engineer would
  receive it: a monitoring alert or a vague user report. No hint about
  root cause.
- **Environment** - what's actually running (a docker-compose stack, a
  containerlab network topology, or a single VM), so you know what
  tools/access you have - not what's wrong.
- **Your task** - find the root cause and fix it, using whatever tools
  you'd normally reach for. You explore on your own.
- **Getting unstuck** - 2-3 non-spoiler nudges if you're completely
  stuck, without giving away the mechanism.
- **`solution.md`** - a full postmortem: root cause, why it happened,
  why the obvious fixes don't work, the investigation that reveals it,
  how to prevent it, and real-world examples of the same pattern.
- **`CONCEPTS.md`** - the interaction between the combined mechanisms
  explained properly, plus curated resources to go deeper.

Every incident ships a turnkey `setup.sh` (builds the entire broken
environment, no manual steps), `check.sh` (verifies the actual
business-facing symptom from the page is resolved - not any specific
internal fix), and `reset.sh` (tears down and rebuilds the incident from
scratch).

## The incidents

1. [`01-the-login-latency-spike`](01-the-login-latency-spike) - login
   latency spikes from 8ms to over a second and 12% of requests fail,
   while CPU and memory both look completely normal.
2. [`02-the-hanging-api-calls`](02-the-hanging-api-calls) - report
   generation hangs for specific customers only, looking like a data or
   database problem until a packet capture says otherwise.
3. [`03-the-cascading-outage`](03-the-cascading-outage) - the
   customer-facing API is failing almost every request, and every
   dashboard points at it - but it isn't the service that's actually
   broken.
4. [`04-the-database-that-hangs`](04-the-database-that-hangs) - writes
   hang for several seconds with no errors anywhere, while reads stay
   fast and CPU/memory look untouched.
5. [`05-the-restart-that-doesnt-help`](05-the-restart-that-doesnt-help) -
   a stuck service that `systemctl restart` can't fix, twice - which
   turns out to be the diagnostic clue itself.

## Prerequisites

- Docker + the `docker compose` plugin (incidents 1, 3, 4)
- Docker + [containerlab](https://containerlab.dev) (incident 2)
- A Linux VM with `sudo` access, no containers required (incident 5)
- The usual troubleshooting toolkit from Levels 1-5: `top`,
  `docker stats`, `iostat`, `tcpdump`, `iptables`, `mysql` client,
  `journalctl`, `/proc`
