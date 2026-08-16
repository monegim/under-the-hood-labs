# Lab 10 — HPA Not Scaling (No metrics-server)

## Objective
Deploy a `HorizontalPodAutoscaler` targeting CPU utilization against a
`kind` cluster that has no metrics pipeline at all, watch it sit forever
unable to scale, diagnose it with `kubectl describe hpa` and `kubectl top`,
then install `metrics-server` correctly (including the flag kind
specifically requires) and confirm it starts working.

## Why this matters
`HorizontalPodAutoscaler` is one of the first things people reach for on a
new cluster, and on `kind` (and plenty of bare-metal/self-managed clusters)
it silently does nothing, because `metrics-server` — the component that
actually answers "how much CPU is this pod using right now" — isn't
installed by default. Managed cloud clusters (EKS, GKE, AKS) usually ship
it or make it a one-click add-on, so engineers who learned Kubernetes
there are often seeing "TARGETS: `<unknown>`/50%" for the first time and
have no idea it means an entire API (`metrics.k8s.io`) is missing, not
that their HPA config is wrong. Worse, `kind` has its own extra gotcha on
top of "metrics-server isn't installed": even after you install it,
metrics-server refuses to scrape kubelets by default because kind's
kubelet serving certificates don't validate under metrics-server's normal
TLS checks — so the very first fix attempt often *still* doesn't work, and
knowing to check the metrics-server pod's own logs for the reason is the
real skill here.

## Prerequisites
- Docker installed and running
- `kind` and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

Cluster creation (handled for you by `setup.sh`):
```bash
kind create cluster --name k8s10
```
(A completely default kind cluster — no CNI swap, no extra config. The
only thing "broken" here is a missing component, not cluster networking.)

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s10` kind cluster, deploys `php-apache` (the exact
image — `registry.k8s.io/hpa-example` — used in the official Kubernetes
HPA walkthrough) with CPU `requests`/`limits` set and a `Service` in front
of it, creates a `HorizontalPodAutoscaler` targeting it at 50% CPU
utilization (1-5 replicas), and deliberately does **not** install
`metrics-server`.

## Step 2 — Confirm the symptom
```bash
kubectl --context kind-k8s10 top pods
kubectl --context kind-k8s10 get hpa php-apache
```
`top pods` fails outright (something like `error: Metrics API not
available`), and `get hpa` shows `TARGETS` stuck at `<unknown>/50%` — not
`0%/50%`, specifically `<unknown>`, because there's no data at all, not
just "no load yet."

## Step 3 — Read the actual diagnosis
```bash
kubectl --context kind-k8s10 describe hpa php-apache
```
Look at the `Conditions` section: `AbleToScale` is fine, but
`ScalingActive` is `False` with reason `FailedGetResourceMetric` and a
message like `unable to get metrics for resource cpu: unable to fetch
metrics from resource metrics API: the server is currently unable to
handle the request (get pods.metrics.k8s.io)`. That's the API server
telling you the `metrics.k8s.io` aggregated API isn't registered by
anything — not a permissions problem, not an HPA config problem.

## Step 4 — Install metrics-server
```bash
CTX=kind-k8s10
kubectl --context "$CTX" apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl --context "$CTX" -n kube-system rollout status deployment/metrics-server --timeout=60s
```
Watch it: on `kind`, this deployment will **not** go Ready. Check why:
```bash
kubectl --context "$CTX" -n kube-system get pods -l k8s-app=metrics-server
kubectl --context "$CTX" -n kube-system logs -l k8s-app=metrics-server
```
The logs show repeated TLS errors scraping kubelets — something like
`x509: cannot validate certificate ... because it doesn't contain any IP
SANs`. kind's kubelet serving certificate is only valid for the specific
names kind generated it for, and metrics-server's default TLS verification
rejects it.

## Step 5 — Fix it: add the flag kind requires
```bash
CTX=kind-k8s10
kubectl --context "$CTX" -n kube-system patch deployment metrics-server --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}
]'
kubectl --context "$CTX" -n kube-system rollout status deployment/metrics-server --timeout=60s
sleep 30
kubectl --context "$CTX" top pods
kubectl --context "$CTX" get hpa php-apache
```
`--kubelet-insecure-tls` tells metrics-server to skip verifying the
kubelet's serving certificate chain (acceptable for a local `kind` lab;
in a real cluster you'd fix the certificate instead — see `CONCEPTS.md`).
Give it 15-30 seconds after rollout — metrics-server polls kubelets on an
interval, it isn't instant. `kubectl top pods` should now return real
numbers, and `TARGETS` on the HPA should flip from `<unknown>` to an
actual percentage.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — metrics-server is healthy, HPA is still `<unknown>`:**
```bash
bash -c '
CTX=kind-k8s10
kubectl --context $CTX create deployment no-requests-app --image=registry.k8s.io/hpa-example
kubectl --context $CTX expose deployment no-requests-app --port=80
cat <<EOF | kubectl --context $CTX apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: no-requests-app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: no-requests-app
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
EOF
sleep 20
kubectl --context $CTX get hpa no-requests-app
kubectl --context $CTX top pod -l app=no-requests-app
'
```
`kubectl top pod` actually works here (metrics-server is fine, proven in
Step 5) — but the HPA still shows `<unknown>`. Use `kubectl describe hpa
no-requests-app` and read the `Message` on `FailedGetResourceMetric`
carefully; it names a completely different missing thing than Step 3 did.
Check the Deployment's container spec for what's absent.

**Challenge B — the HPA targets something that isn't there:**
```bash
bash -c '
CTX=kind-k8s10
cat <<EOF | kubectl --context $CTX apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: typo-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php-apache-prod
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
EOF
kubectl --context $CTX describe hpa typo-hpa
'
```
This one never even gets to the metrics question. Read the `Conditions`
section — the condition type that's failing here is different from
`ScalingActive`/`FailedGetResourceMetric` in Steps 2-3. Figure out which
object name Kubernetes thinks doesn't exist, and why that's a scale-target
problem rather than a metrics-pipeline problem.

See `solution.md` only after you've formed your own diagnosis.
