# Incident 06 — The Rollout That Lied

## The page

> checkout-api was redeployed twenty minutes ago. `kubectl rollout
> status` reported success, every pod shows `Running` and `1/1 Ready`,
> and the dashboard shows nothing red. Support is now getting a steady
> stream of "checkout is broken" tickets that started right around the
> same time. Nobody's paging on pod health, because by every signal
> Kubernetes reports, this deployment is fine.

The rollout itself did not fail. It is not stuck, not crash-looping, not
`ImagePullBackOff`. Every pod that's supposed to be up, is up, and
Kubernetes considers every one of them healthy.

## Environment

A `kind` cluster brought up by `setup.sh`:
- `postgres` — Postgres 16, single instance, one `orders` table.
- `checkout-api` — a small Flask Deployment (3 replicas) in front of
  Postgres, exposed via a Service. `setup.sh` deploys a known-good
  revision first and proves it actually works, then rolls out a second
  revision — the one live when you start investigating.

You have full `kubectl` access to the cluster, plus whatever you can
reach by port-forwarding the `checkout-api` Service.

## Your task

Find the root cause and fix it. Use whatever tools you'd normally reach
for (`kubectl describe`, `kubectl logs`, `kubectl rollout history`,
actually calling the service). There's no prescribed sequence — start
from the page above and follow the evidence.

## Getting unstuck

- Every standard Kubernetes health signal (`kubectl get pods`, rollout
  status, readiness) is telling you this is fine. If those signals
  can't see the actual problem, what would you have to do that's
  different from checking them?
- Send a *real* request through the service the way a customer would,
  not just a health check. Does it succeed?
- `kubectl rollout history` shows there were two revisions. What's
  actually different between them — not what the commit message says
  changed, what the manifests themselves say?

See `solution.md` only after you've formed your own diagnosis, or if
you're completely stuck after trying the nudges above.
