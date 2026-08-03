# Incident 01 — Concept: Connection Pool Exhaustion and Retry Amplification

## What's actually going on

Two mechanisms interact here, and neither one alone produces the exact
symptom on the page.

The first is a **shared, finite resource ceiling**: MySQL's
`max_connections` isn't per-client or per-application, it's a single
number the whole server enforces across every connection from every
source - the login service's pool, the reconciler job, `mysqldump`, a
DBA's interactive session, all of it draws from the same budget. Nothing
in MySQL's architecture reserves a slice of that budget for "the
important traffic" by default; a misbehaving consumer with no coordi-
nation (like this lab's reconciler, opening 26 raw connections and
holding each one busy indefinitely) can silently eat almost the entire
budget, and every other consumer just sees "sometimes I can't connect,"
indistinguishable from the server being overloaded or down.

The second mechanism is what turns a hard, binary failure
("connection refused") into the specific *soft, latency-shaped* symptom
described on the page. The login service's retry-with-backoff logic
(three attempts, 400ms apart) is a completely reasonable, standard
defensive pattern - exactly what you'd want against a transient blip.
But against a *sustained* resource exhaustion, that same defensive
pattern doesn't fail fast; it fails slow. Every request that eventually
succeeds pays the cost of however many failed attempts came before it,
which is exactly why the symptom is "8ms became 1.2s," not "8ms became
an instant error." Retries are a good idea against transient failures and
a bad idea against a starved shared resource - the same code is correct
in one situation and actively harmful (masking the real signal, making
an outage last longer per-request) in the other, and there is no way to
tell which situation you're in from inside the retry loop itself. This is
precisely the kind of interaction the USE method (Utilization, Saturation,
Errors) is built to catch: checking the *saturation* of a resource
(`Threads_connected` against `max_connections`), not just whether it
errors outright, is what actually reveals this - CPU/memory utilization
checks (which the page already ruled out) tell you nothing about a
connection-count ceiling.

## Where this shows up in the real world

Any architecture with more than one process talking to the same
database - which is nearly all of them - has this failure mode latent in
it. Background job frameworks (Sidekiq, Celery, Resque), ETL/backfill
scripts, monitoring/reporting tools, and ORMs with their own connection
pooling all draw from the same server-side ceiling as the request-serving
path, usually with zero built-in coordination between them. The retry-
amplification half is just as common: any client library with sensible-
looking retry/backoff defaults will convert a hard resource-exhaustion
failure into a latency spike instead of a clean error, which is often
*harder* to triage under pressure because dashboards showing "elevated
latency" read very differently from dashboards showing "connection
refused" - even though they can be the exact same root cause.

## Go deeper

- **Book:** *Site Reliability Engineering* — Google, ed. Betsy Beyer et
  al. (free at https://sre.google/books/) — see the chapters on
  addressing cascading failures and overload, directly applicable to
  shared-resource starvation like this.
- **Book:** *Systems Performance* — Brendan Gregg — general methodology
  for identifying saturation of a resource, not just errors or
  utilization, as the actual bottleneck.
- **Website:** Brendan Gregg's site — https://www.brendangregg.com — the
  USE method (Utilization/Saturation/Errors) is exactly the checklist
  that would have caught "connections are saturated" faster than staring
  at CPU and memory.
- **Website:** https://sre.google/books/ — same as above, browsable
  online.
