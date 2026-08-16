# Lab 11 — Resource Quota Exceeded

## Objective
Fill a namespace's `ResourceQuota` up with baseline workloads, hit it with
a new Pod that pushes past the CPU limit, and learn to read
`kubectl describe resourcequota`'s used-vs-hard columns instead of
mistaking the resulting `Forbidden` error for an RBAC or syntax problem.

## Why this matters
`ResourceQuota` objects are how multi-tenant clusters stop one team's
namespace from starving every other team of CPU/memory, and the error
they produce on a blocked `kubectl apply`/`kubectl create` is genuinely
easy to misread: it's a `403 Forbidden` from the API server, the exact
same HTTP status an RBAC denial produces, and the message doesn't scream
"quota" unless you actually read it. Engineers who've learned to
associate `Forbidden` with "I don't have permission" go straight to
checking `Role`/`RoleBinding` objects — which are completely fine here —
and waste real time before noticing the error text says `exceeded quota`,
not `cannot create resource`. Worse, the quota can get exhausted by
something that isn't even the request in front of you: leftover
Completed Jobs, a teammate's forgotten test Deployment, or normal
autoscaling — so "my one Pod looks fine, why is this Forbidden" is a
common, genuinely confusing on-call moment.

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
kind create cluster --name k8s11
```

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s11` kind cluster, then in a namespace called
`team-a`:
- applies a `ResourceQuota` named `compute-quota` capping the namespace at
  `requests.cpu: 1` (1000m), `requests.memory: 1000Mi`,
  `limits.cpu: 2` (2000m), `limits.memory: 2000Mi`
- deploys two baseline Pods (`app-1`, `app-2`), each requesting
  `cpu: 400m` / `memory: 400Mi` with `limits` of `cpu: 800m` /
  `memory: 800Mi` — together they use `800m`/`800Mi` of the
  `1000m`/`1000Mi` request quota, leaving only `200m`/`200Mi` of headroom
- attempts to create a third Pod, `app-3`, requesting `cpu: 300m` /
  `memory: 300Mi` — enough to push the namespace past both request
  quotas at once

## Step 2 — Confirm the symptom
```bash
kubectl --context kind-k8s11 -n team-a apply -f /tmp/lab11-app-3.yaml
```
(`setup.sh` writes this file for you and shows you the exact command.)
This fails with something like:
```
Error from server (Forbidden): error when creating "/tmp/lab11-app-3.yaml": pods "app-3" is forbidden: exceeded quota: compute-quota, requested: requests.cpu=300m,requests.memory=300Mi, used: requests.cpu=800m,requests.memory=800Mi, limited: requests.cpu=1,requests.memory=1000Mi
```

## Step 3 — Rule out RBAC first (don't skip this step)
```bash
kubectl --context kind-k8s11 auth can-i create pods -n team-a
```
This returns `yes`. Whoever is running these commands has full permission
to create Pods in `team-a` — the `Forbidden` above has nothing to do with
RBAC. This is the single fastest way to rule out "am I even allowed to do
this" before spending time anywhere else.

## Step 4 — Read the quota's used-vs-hard columns
```bash
kubectl --context kind-k8s11 -n team-a get resourcequota
kubectl --context kind-k8s11 -n team-a describe resourcequota compute-quota
```
`describe` prints a table with `Used` and `Hard` columns side by side:
`requests.cpu` shows `800m` used against a `1` hard limit — only `200m`
of headroom exists, and `app-3` asked for `300m`. The error in Step 2
already told you the exact numbers; this step confirms them independently
against the quota object itself.

## Step 5 — Fix it: fit inside the remaining headroom
```bash
cat <<EOF | kubectl --context kind-k8s11 apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-3
  namespace: team-a
  labels:
    app: app-3
spec:
  containers:
    - name: app-3
      image: nginx
      resources:
        requests:
          cpu: "150m"
          memory: "150Mi"
        limits:
          cpu: "300m"
          memory: "300Mi"
EOF
```
Reducing the request to `150m` fits inside the remaining `200m` of quota
headroom, so this now succeeds. In a real incident the other valid fixes
are deleting/scaling down something else in the namespace to free
capacity, or — if the extra capacity is a legitimate, approved need —
raising `compute-quota`'s `hard` values. Which one is right depends on
whether the namespace is actually supposed to be this busy; `describe
resourcequota` gives you the numbers, not the judgment call.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a Deployment scale-up silently stalls, not a direct `apply` error:**
```bash
bash -c '
CTX=kind-k8s11
kubectl --context $CTX -n team-a create deployment app-4 --image=nginx --replicas=1 \
  --overrides="{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"app-4\",\"image\":\"nginx\",\"resources\":{\"requests\":{\"cpu\":\"100m\",\"memory\":\"100Mi\"},\"limits\":{\"cpu\":\"200m\",\"memory\":\"200Mi\"}}}]}}}}"
kubectl --context $CTX -n team-a scale deployment app-4 --replicas=5
sleep 5
kubectl --context $CTX -n team-a get deployment app-4
kubectl --context $CTX -n team-a get replicaset -l app=app-4
'
```
`kubectl apply`/`scale` itself reports success — no `Forbidden` error
appears anywhere on your terminal. Yet `app-4` never reaches 5/5 Ready.
The rejection happened one level down. Find it with `kubectl describe
replicaset -n team-a -l app=app-4` (check its Events), not by staring at
the Deployment.

**Challenge B — quota rejects the Pod outright, before checking any number:**
```bash
bash -c '
CTX=kind-k8s11
kubectl --context $CTX -n team-a run app-5 --image=nginx --restart=Never
'
```
This fails immediately too, but the error text is nothing like Step 2's
`exceeded quota` message. Read it closely — it names specific resource
fields rather than a used/hard comparison. Figure out what triggers this
distinct rejection path, and why it happens regardless of how much quota
headroom is actually left.

See `solution.md` only after you've formed your own diagnosis.
