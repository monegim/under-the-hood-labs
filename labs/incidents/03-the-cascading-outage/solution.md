# Incident 03 — Solution

## Root cause

`auth-service`'s `/validate` handler opens a per-call audit-log file and
never closes it (`auth/app.py`, `_leaked_handles`). The container's
`nofile` ulimit is capped at 50 (`docker-compose.yml`). `setup.sh` alone
drives 80 calls directly at `auth` before you even start looking, so by
the time you investigate, `auth` has already burned through its entire
file-descriptor budget - every `open()` call for a new audit-log file
now raises `OSError: [Errno 24] Too many open files`.

`auth`'s handler *does* catch that error and return a clean `500`
rather than crashing - so the process never exits, never restarts, and
`docker ps` shows it as healthy the entire time. `orders-service` calls
`auth`'s `/validate` on every single request it serves; when that call
comes back as a `500`, `orders` has nothing left to do but fail the
customer's request too. The result: `orders` fails almost 100% of its
traffic, `orders` is where every dashboard and alert points, and `auth`
- the actual broken component - never crashes, never restarts, and
never shows up as anything worse than "running."

## Why it happened

Writing an audit-log entry per validation is a completely reasonable
thing to want; forgetting to close the file handle afterward is an
easy, common mistake (the fix is a two-character `with` block). In
production this kind of leak can take days or weeks to matter, because
most containers/services get a nofile limit in the thousands or tens of
thousands - it fails eventually, just unpredictably far from the change
that introduced it, which makes it very hard to connect back to a
specific deploy. This lab compresses that timeline by capping the
limit at 50 so the leak becomes fatal within a couple minutes instead
of a couple weeks - the mechanism is identical either way.

## Why the obvious fixes don't work

- **Restarting `orders`**: does nothing - `orders`'s own process is
  completely healthy. It will make the exact same failing call to
  `auth` immediately after restarting.
- **Scaling `orders` to more replicas**: doesn't help and can make
  things marginally worse - every replica still calls the same
  exhausted `auth` instance for every request.
- **Retrying the request, or raising `orders`'s timeout to `auth`**:
  doesn't help - `auth` isn't slow, it's returning a fast, deterministic
  `500` for every validate call. More retries just means more fast
  failures, not eventual success.
- **Checking "what changed in orders' deploy today"**: a dead end by
  design - the page states nothing was deployed to `orders` today, and
  there's no code change in `auth` either. This is a slow-building leak
  crossing a threshold, not a regression from a recent change - a
  different category of incident from "the last deploy broke it."

## The investigation

Confirm the customer-facing symptom, and read the error `orders` itself
is reporting - don't stop at "orders returns 500":
```bash
curl -s http://localhost:8001/orders/123
docker logs incident03-orders --tail 20
```
The response body says `"error": "auth service unavailable"` with a
`detail` field showing a `500` coming back from `auth` specifically -
`orders` is accurately reporting that its dependency failed, not
inventing its own bug.

Follow the dependency and hit `auth` directly, the same way `orders`
does:
```bash
curl -s -X POST http://localhost:8000/validate
```
This returns the actual smoking gun: `{"valid": false, "error": "[Errno
24] Too many open files: '/tmp/audit-....log'"}` - `Errno 24` is
`EMFILE`, the per-process open-file limit (same signature as
`labs/linux/16-too-many-open-files`).

Confirm the ceiling and current usage directly:
```bash
docker exec incident03-auth cat /proc/1/limits | grep -i "open files"
docker exec incident03-auth ls /proc/1/fd | wc -l
```
`Max open files` shows `50` (soft and hard); the fd count sits right at
that ceiling.

Note what `docker ps` does and doesn't tell you:
```bash
docker ps --filter name=incident03
```
Both containers show `Up ...` - "running" only means the main process
hasn't exited. It says nothing about whether the process can still do
its job, which is exactly the gap this incident lives in.

## The fix

Immediate mitigation - restart `auth` to reclaim all of its leaked file
descriptors:
```bash
docker compose restart auth
curl -s -X POST http://localhost:8000/validate
curl -s http://localhost:8001/orders/123
```
Both should now succeed. This is only a mitigation, though: the code
still leaks one file handle per call, so left running long enough, the
exact same failure recurs. The real fix is closing the file handle
after use (`with open(path, "a") as f: ...`) so nothing accumulates in
the first place - raising the ulimit or restarting periodically only
buys time, it doesn't fix the leak.

## Real-world examples of this pattern

- Long-running Java/Node.js/Python services that leak file handles or
  sockets (an unclosed HTTP client, an unclosed DB cursor, an unclosed
  temp file) eventually hit `ulimit -n` days or weeks after the leaky
  code shipped, with no obvious connection back to that deploy.
- Any microservice dependency chain where an internal, rarely-alerted-on
  service (auth, config, feature-flag, session-store) degrades and every
  downstream consumer lights up instead - the downstream services are
  usually where dashboards and paging are configured, since they're
  user-facing, which means the first responder is very often looking at
  the wrong service by default, exactly as in this incident.
- "The container is running but not working" is one of the most common
  gaps in naive health checks/monitoring - a healthcheck that only
  confirms the process is alive (or hits a trivial endpoint) can stay
  green through this entire incident, which is why deep health checks
  that exercise the real code path matter.
