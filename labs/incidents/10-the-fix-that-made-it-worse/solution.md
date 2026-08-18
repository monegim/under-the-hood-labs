# Incident 10 — Solution

## Root cause

`client-traffic.service` retries every failed checkout attempt up to
3 more times, immediately, with no delay between attempts. `backend`'s
capacity hasn't changed at all — it's the same fixed-size worker pool
it's always been, still able to absorb its normal recurring traffic
bursts with the same ~40% failure rate it's always had (that rate was
never zero; the service was sized for average load, and bursts have
always pushed some requests past their timeout while waiting for a
free worker). What changed is that every one of those failures now
generates up to 3 additional attempts, immediately, into a backend
that's already at capacity and already the reason the *first* attempt
failed. Each retry wave adds more queued work on top of a backend
that hasn't finished draining the previous wave, and the next
recurring burst arrives before that's cleared either. The backlog
never has a chance to shrink — it only grows, burst after burst,
until essentially every request (original or retry) is waiting behind
so much queued work that it times out too.

## Why it happened

Retrying a failed request is a reasonable, common way to make an
individual user's request more likely to eventually succeed — and in
isolation, against a backend with spare capacity, it does exactly
that. The mistake isn't retrying; it's retrying into a backend that's
failing *because it's already at capacity*, where every retry adds
directly to the exact condition causing the failures in the first
place. A fix aimed at "reduce how often any single user sees an
error" and a fix aimed at "reduce total load on an already-strained
backend" can point in opposite directions, and nothing about adding a
retry policy makes that tension visible until the backend is
genuinely under real, sustained pressure — which a quick test against
an idle backend would never reveal.

## Why the obvious fixes don't work

- **Restarting `backend.service`**: clears the queue for a moment,
  but `client-traffic.service` is still configured with the same
  retry policy and the recurring bursts haven't stopped — the backlog
  starts rebuilding on the very next burst.
- **Restarting `client-traffic.service`** (without changing its
  config): resets its counters, which can make things look briefly
  better in a log or dashboard, but the underlying `RETRIES=3`
  configuration is untouched — the exact same compounding resumes
  within the next couple of burst cycles.
- **Scaling `backend` up**: genuinely helps, by giving the system more
  raw capacity to absorb the retry-amplified load — but it's treating
  the symptom at a real cost, not the cause. The retry policy still
  multiplies every burst's real load by up to 4x; scaling capacity to
  match that multiplied load, forever, instead of removing the
  multiplication, is solving a self-inflicted problem with
  infrastructure spend.

## The investigation

Confirm the symptom is real and ongoing:
```bash
sudo journalctl -u client-traffic -n 5 --no-pager
```
A recent cumulative report showing a failure rate at or near 100%,
not the ~40% this service is expected to run at during a burst.

Compare checkout attempts against actual HTTP requests sent — this is
the number that reveals amplification directly:
```bash
sudo journalctl -u client-traffic --no-pager | grep "checkout attempts" | tail -5
```
Total HTTP requests climbing far faster than checkout attempts —
several times as many requests being sent as there are real logical
checkouts being attempted.

Confirm what's actually configured:
```bash
sudo systemctl cat client-traffic.service | grep RETRIES
```
`Environment=RETRIES=3`.

## The fix

```bash
sudo sed -i 's/Environment=RETRIES=3/Environment=RETRIES=0/' /etc/systemd/system/client-traffic.service
sudo systemctl daemon-reload
sudo systemctl restart client-traffic.service
```
Within the next report cycle, the failure rate settles back to its
normal, stable ~40% during bursts, and total HTTP requests track
1-for-1 with actual checkout attempts again — the backend was never
the problem; it's handling exactly the load it was always sized for.

A more durable version of this fix keeps retries (they're genuinely
useful when the backend *does* have room) but adds real backoff
between attempts and a cap on total retried load, so a retry policy
can help an individual request without being able to multiply an
already-overloaded backend's traffic by several times over.

## Real-world examples of this pattern

- Client-side retry logic with no backoff or jitter is one of the
  most common self-inflicted outage amplifiers in distributed
  systems — it's the textbook mechanism behind "thundering herd"
  incidents, where a brief, recoverable blip turns into a sustained
  outage purely because every client's automatic recovery behavior
  adds load at exactly the moment the system can least afford it.
- This is the same underlying shape as
  `labs/incidents/09-the-shared-proxy-meltdown` (a finite, shared
  capacity overwhelmed by more demand than it was sized for) with one
  extra twist: there, the extra demand came from an unrelated
  service; here, it comes from the *fix itself*, deployed with good
  intentions and reasoned about correctly in isolation, but not
  against the system it actually landed on under real load.
- Real incident response playbooks for exactly this reason usually
  call for exponential backoff with jitter, and often a circuit
  breaker that stops retrying (and stops sending new traffic
  altogether) once a backend's failure rate crosses a threshold —
  both exist specifically to prevent a well-intentioned retry policy
  from becoming the actual cause of an outage.
