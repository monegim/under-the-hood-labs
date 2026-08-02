# Lab 1 — Pod Networking Broken (NetworkPolicy Default-Deny)

## Objective
Break in-cluster pod-to-pod connectivity with a `NetworkPolicy` default-deny
rule that's missing the allow rule it needs, diagnose it with the exact
tools you'd use on a real cluster, then fix it.

## Why this matters
"It worked five minutes ago and now the frontend can't reach the backend"
is one of the most common Kubernetes incidents, and NetworkPolicies are a
frequent silent cause: someone locks down a namespace for security
("default-deny ingress") and forgets — or gets wrong — the allow rule for
a legitimate caller. Unlike a crash, this produces no error in the backend
pod's logs at all; from the backend's point of view, the traffic just
never arrives. Knowing to check `NetworkPolicy` objects (not just pod
logs) before assuming a code bug is the difference between a five-minute
diagnosis and an hour of guessing.

As in the [Kubernetes Internals lab](../../linux/06-kubernetes-internals),
a Service with no endpoints produces instant `ECONNREFUSED`. This lab is
different on purpose: the Service has healthy endpoints the whole time —
the packets are arriving at the node and getting dropped by policy, which
is a much quieter, more confusing failure to track down.

## Prerequisites
- Docker installed and running
- `kind` and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

> **Note:** kind's default CNI (`kindnetd`) does **not** enforce
> `NetworkPolicy` objects at all — they'd silently do nothing. To make
> policies actually take effect, this lab disables the default CNI and
> installs Calico instead. That's what the cluster config below is for.

Cluster creation (this is what `setup.sh` runs for you — shown here so you
can see exactly what's being built):
```bash
cat <<'EOF' > /tmp/lab-k8s01-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  podSubnet: "192.168.0.0/16"
EOF
kind create cluster --name k8s01 --config /tmp/lab-k8s01-config.yaml
kubectl --context kind-k8s01 apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
```
(Check https://github.com/projectcalico/calico/releases for a newer tag —
this lab was written against v3.28.0. Calico's pods take a minute or two
to go Ready after this; `setup.sh` waits for them.)

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s01` kind cluster with Calico (as above), waits for
Calico to be Ready, then in a namespace called `shop`:
- deploys `backend` (nginx) + a `backend-svc` Service in front of it
- deploys `frontend` (a long-running `curlimages/curl` pod you can
  `kubectl exec` into)
- confirms `frontend` can reach `backend-svc` (baseline: works)
- applies a default-deny-ingress `NetworkPolicy` to the `shop` namespace
- **does not** add any allow rule back — this is the bug

## Step 2 — Confirm the baseline is now broken
```bash
kubectl --context kind-k8s01 -n shop exec frontend -- curl -m 3 -sS http://backend-svc
```
This times out (not "connection refused" — a real TCP-level timeout,
because packets are being dropped, not rejected).

## Step 3 — Rule out the obvious things first
```bash
kubectl --context kind-k8s01 -n shop get pods -o wide
kubectl --context kind-k8s01 -n shop get endpoints backend-svc
```
The backend pod is Running/Ready and `backend-svc` has a real endpoint IP.
This is **not** the "Service with no endpoints" failure from the
Kubernetes Internals lab — the wiring is fine. Something else is dropping
the traffic in flight.

## Step 4 — Check NetworkPolicies
```bash
kubectl --context kind-k8s01 -n shop get networkpolicy
kubectl --context kind-k8s01 -n shop describe networkpolicy default-deny-ingress
```
`describe` shows a policy selecting all pods (`PodSelector: <none>
(Allowing all pods in this namespace)`) with `Policy Types: Ingress` and
**no** `Allowing ingress traffic` rules listed at all — every pod in the
namespace now rejects all ingress by default, and nothing has been
allowed back in.

## Step 5 — Fix it: add the missing allow rule
```bash
cat <<'EOF' | kubectl --context kind-k8s01 apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: shop
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 80
EOF
kubectl --context kind-k8s01 -n shop exec frontend -- curl -m 3 -sS http://backend-svc
```
This now succeeds (nginx's welcome page HTML comes back).

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — the allow rule exists but still doesn't work:**
```bash
bash -c '
kubectl --context kind-k8s01 -n shop delete networkpolicy allow-frontend-to-backend
cat <<EOF | kubectl --context kind-k8s01 apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: shop
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: front-end
      ports:
        - protocol: TCP
          port: 80
EOF
'
kubectl --context kind-k8s01 -n shop exec frontend -- curl -m 3 -sS http://backend-svc
```
Someone wrote an allow rule, and it still fails. Diagnose exactly why
this rule doesn't match the traffic it's supposed to allow — don't just
assume it's a typo, prove it with `kubectl describe networkpolicy` and
`kubectl get pod frontend --show-labels`.

**Challenge B — a different pair, a different symptom:**
```bash
kubectl --context kind-k8s01 -n shop delete networkpolicy default-deny-ingress
kubectl --context kind-k8s01 -n shop patch svc backend-svc -p '{"spec":{"selector":{"app":"backendd"}}}'
kubectl --context kind-k8s01 -n shop exec frontend -- curl -m 3 -sS http://backend-svc
```
This time the NetworkPolicy is not the problem. Compare the *failure mode*
you see here (immediate response, not a timeout) to Steps 2-4 above, and
figure out what's actually broken and why the symptom is so different from
a NetworkPolicy issue — check `kubectl get endpoints backend-svc` before
you conclude anything.

See `solution.md` only after you've formed your own diagnosis.
