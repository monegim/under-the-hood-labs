# Lab 10 — Solutions

## Challenge A — metrics-server works, but the target has no CPU requests

**Check:**
```bash
kubectl --context kind-k8s10 describe hpa no-requests-app
kubectl --context kind-k8s10 get deployment no-requests-app -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
```
`describe hpa` shows `FailedGetResourceMetric` with a message like
`unable to get metrics for resource cpu: unable to get resource
utilization: missing request for cpu in container "no-requests-app" of
Pod ...`. The Deployment's `resources` field is empty — no
`requests.cpu` was ever set.

**Diagnosis:** metrics-server reporting real usage numbers isn't enough.
The HPA computes *utilization* as a percentage: `currentUsage /
requestedAmount`. Without a `requests.cpu` on the container, there's no
denominator — the HPA controller has actual millicore usage data (proven
by `kubectl top pod` working) but literally cannot compute a percentage
from it, so it reports the metric as unavailable rather than guessing.
This is a completely different failure than Steps 2-3: there, no data
existed anywhere; here, the data exists but the math is undefined.

**Fix:**
```bash
kubectl --context kind-k8s10 patch deployment no-requests-app --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/resources","value":{"requests":{"cpu":"200m"}}}
]'
sleep 20
kubectl --context kind-k8s10 get hpa no-requests-app
```

**Lesson:** `<unknown>` on an HPA has (at least) two unrelated root
causes that produce the exact same column output: no metrics pipeline
(Steps 2-3, fixed by installing metrics-server) and no resource requests
on the target (this challenge, fixed by editing the Deployment, not
touching metrics-server at all). `kubectl describe hpa`'s `Message` field
is the only thing that tells you which one you're looking at — the
`TARGETS` column alone is not enough to diagnose from.

---

## Challenge B — scaleTargetRef points at a Deployment that doesn't exist

**Check:**
```bash
kubectl --context kind-k8s10 describe hpa typo-hpa
```
The relevant condition is `AbleToScale`, not `ScalingActive` — `False`,
reason `FailedGetScale`, message something like `deployments/scale.apps
"php-apache-prod" not found`.

**Diagnosis:** `scaleTargetRef.name` was set to `php-apache-prod`, but the
actual Deployment is named `php-apache`. The HPA controller's first job,
before it ever asks about metrics, is resolving `scaleTargetRef` to a
`scale` subresource it can read current replica count from and write
desired replica count to. If that lookup fails, the controller never gets
as far as asking `metrics.k8s.io` anything — which is why this shows up
under `AbleToScale`/`FailedGetScale` rather than
`ScalingActive`/`FailedGetResourceMetric`.

**Fix:**
```bash
kubectl --context kind-k8s10 patch hpa typo-hpa --type=json -p='[
  {"op":"replace","path":"/spec/scaleTargetRef/name","value":"php-apache"}
]'
kubectl --context kind-k8s10 describe hpa typo-hpa
```

**Lesson:** `kubectl describe hpa`'s `Conditions` block has two
independent failure axes — `AbleToScale` (can it find and talk to the
target at all) and `ScalingActive` (can it read the metric it needs) —
and they fail for completely different reasons. Reading *which* condition
is `False`, not just seeing "something is False," tells you whether
you're chasing a naming/reference bug (this challenge) or a
metrics-pipeline bug (Steps 2-3).
