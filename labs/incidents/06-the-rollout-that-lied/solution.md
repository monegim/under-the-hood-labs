# Incident 06 — Solution

## Root cause

`checkout-api`'s revision 2 manifest sets an environment variable named
`DB_PASSWROD` — a typo — instead of `DB_PASSWORD`. `app.py` reads the
database password with `os.environ.get("DB_PASSWORD", "")`, so every v2
pod starts with an **empty string** as its Postgres password instead of
the real one. Postgres itself was never touched — the real password is
still exactly what it always was — the app is just authenticating with
the wrong (empty) one, so every `POST /checkout` fails at
`psycopg2.connect()` with an authentication error, caught by the
route's `try/except` and returned as a `500`.

Nothing about this is visible to Kubernetes because the readiness and
liveness probes both hit `/healthz`, which only confirms the Flask
process itself is up and listening — it never opens a connection to
Postgres. That endpoint is identical between v1 and v2, so it passes
instantly for both, the rollout proceeds exactly as designed, and
`kubectl rollout status` correctly reports success — for the thing it's
actually checking, which is "did new pods reach Ready," not "does the
service actually work."

## Why it happened

A one-line environment variable change got bundled into the same
deployment as an unrelated code tweak, and nothing in the pipeline
validates that an env var *name* is correct — `DB_PASSWROD` is a
perfectly legal Kubernetes environment variable name, just not the one
`app.py` happens to read. This is not a Kubernetes bug or a strange edge
case: readiness/liveness probes are deliberately shallow by design (you
don't want your liveness probe itself becoming a source of cascading
failure by depending on every downstream system), and that's the right
default — it's the *coverage gap* that's the problem. Nobody decided
"we're okay finding out about DB auth failures from support tickets" —
it fell out of a probe that was never designed to catch this specific
class of failure, on a service where it turned out to matter.

## Why the obvious fixes don't work

- **Restarting the pods**: they come right back up, pass the same
  shallow health check, and fail the same way — nothing about a restart
  touches the env var.
- **Scaling the Deployment up or down**: every replica is running the
  same broken revision 2 spec; more or fewer copies of the same mistake
  changes nothing.
- **Checking `kubectl get pods` more carefully / waiting longer**: there
  is nothing to see there. Every pod is genuinely, correctly `Ready` by
  the definition Kubernetes is using. The signal you'd normally check
  first is not lying about what it measures — it's just not measuring
  the thing that broke.
- **Blaming Postgres**: `postgres`'s own pod is healthy, its actual
  password never changed, and it's correctly rejecting an
  authentication attempt with a wrong (empty) credential — Postgres is
  behaving exactly as it should.

## The investigation

Every standard health signal says this is fine:
```bash
kubectl --context kind-incident06 get pods -l app=checkout-api
kubectl --context kind-incident06 rollout status deployment/checkout-api
```
All `Running`, `1/1 Ready`, rollout reports `successfully rolled out`.

Send a real request instead of trusting the probe:
```bash
kubectl --context kind-incident06 port-forward svc/checkout-api 18080:80 &
curl -s -X POST http://localhost:18080/checkout \
  -H "Content-Type: application/json" -d '{"item":"widget"}'
```
This returns a 500 with `"error":"checkout failed"` and a Postgres
authentication error in `detail`.

Check the pod's own logs — the actual exception, not the health status:
```bash
kubectl --context kind-incident06 logs -l app=checkout-api --tail=50
```

Compare the two revisions directly rather than guessing what changed:
```bash
kubectl --context kind-incident06 rollout history deployment/checkout-api
diff manifests/checkout-api-v1.yaml manifests/checkout-api-v2.yaml
```
The `env:` block is the only meaningful difference — `DB_PASSWORD` in
v1, `DB_PASSWROD` in v2.

## The fix

Fastest path — roll back to the last known-good revision, which never
had the typo:
```bash
kubectl --context kind-incident06 rollout undo deployment/checkout-api
kubectl --context kind-incident06 rollout status deployment/checkout-api
```
The real forward fix is the same one-line correction, applied properly:
`manifests/checkout-api-v1.yaml` already has `DB_PASSWORD` spelled
correctly — the actual PR fix is renaming `DB_PASSWROD` back to
`DB_PASSWORD` in whatever manifest/values file introduced the typo, then
redeploying that corrected revision forward (not staying rolled back
indefinitely on the old one).

Confirm with a real request again — not just `kubectl get pods`:
```bash
curl -s -X POST http://localhost:18080/checkout \
  -H "Content-Type: application/json" -d '{"item":"widget"}'
```

The durable fix isn't just this one typo — it's closing the coverage
gap: add a deploy-time smoke test that exercises the actual
customer-facing path (a real `POST /checkout`, the way `setup.sh`
itself validates v1 before ever touching v2) as a required gate before a
rollout is considered done, since "every pod passed its probe" and "the
service works" turned out to be two different claims.

## Real-world examples of this pattern

- Env-var and config typos causing silent database auth failures are a
  perennial cause of "deploy looked clean, real traffic broke" incidents
  — the failure mode isn't specific to Kubernetes, but Kubernetes's
  rollout-status-follows-readiness-probe design means a shallow probe
  will *always* report success regardless of what's actually broken
  downstream, which is a sharper version of the same trap.
- This is exactly why Kubernetes' own documentation distinguishes
  liveness/readiness probes from deeper application health checks, and
  why many teams add a separate post-deploy smoke-test or canary-traffic
  step rather than trusting probe status alone as the definition of "the
  rollout succeeded."
