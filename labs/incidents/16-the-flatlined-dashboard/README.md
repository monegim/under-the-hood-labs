# Incident 16 — The Flatlined Dashboard

## The page

> Customers are complaining that the order API is "slow, sometimes,"
> starting about twenty minutes ago. You pull up the service dashboard
> to confirm - CPU load and request latency are both flat, well within
> normal range, no spikes anywhere on the graph. Whatever customers are
> seeing, the dashboard says everything is fine.

Nothing on the graph moved. The page still came in anyway.

## Environment

A single VM running:
- `orders-api.service` - a small HTTP service (`GET /work`, `GET
  /health`) standing in for the order API. `/work` does a short
  CPU-bound computation per request, the same shape as real request
  handling (serialization, validation, etc.).
- `metrics-agent.service` - a background collector that samples system
  load and `orders-api` latency every few seconds and exposes the
  latest snapshot over HTTP on port 9100 at `/metrics`, the same role a
  node_exporter/Telegraf-style agent plays in front of a real
  Prometheus/Grafana setup. It also durably persists every snapshot to
  a network-mounted path (`/mnt/metricslab`, backed by NFS) - a
  compliance requirement someone added so metrics survive a VM rebuild.
- The NFS mount itself, exported and mounted on the same VM (the same
  reproducible-without-a-second-host trick used elsewhere in this
  repo).

You have `sudo` access and the usual tools: `curl`, `top`, `ps -eo
stat,wchan,cmd`, `/proc`, `mount`, `iptables`.

## Your task

Find the root cause and fix it. Use whatever tools you'd normally reach
for. There's no prescribed sequence - explore the environment the way
you would a real page, starting from the symptom above. Note that there
may be more than one thing wrong here.

## Getting unstuck

- The dashboard and the real system are two different things being
  asked the same question. If they disagree, what would make the
  *dashboard's* answer wrong without the *system's* answer changing?
  What field in a scrape response would tell you which one to trust?
- `curl http://localhost:8080/work` directly, timing it yourself,
  costs nothing and bypasses the dashboard entirely. Compare that
  against what port 9100 is reporting for the same moment in time.
- `metrics-agent` writes to more than one place. If one of those places
  stopped responding, would the process necessarily crash, hang
  entirely, or just... stop making progress on part of what it does?
  `ps -eo pid,stat,wchan:32,cmd` distinguishes "busy" from "blocked" from
  "dead."

See `solution.md` only after you've formed your own diagnosis, or if
you're completely stuck after trying the nudges above.
