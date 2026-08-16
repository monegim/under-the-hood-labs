# Lab 15 — RBAC Misconfiguration

## Objective
Run a Pod under a ServiceAccount with no permissions granted, watch it
fail with `Forbidden` against the real API server (not a synthetic
check), fix it with a `Role` + `RoleBinding`, then learn two ways RBAC
"looks" configured but isn't actually granting what you think.

## Why this matters
Almost everything that talks to the Kubernetes API from inside the
cluster — controllers, operators, CI/CD bots, sidecars doing service
discovery — authenticates as a `ServiceAccount`, and by default a
ServiceAccount can do essentially nothing beyond identify itself. RBAC
is entirely additive: permissions only ever come from `Role`/`ClusterRole`
objects bound to that identity via `RoleBinding`/`ClusterRoleBinding`,
and every piece has to be right — the right verb, the right resource,
the right binding, in the right place — or the request is denied with no
partial credit. This is one of the most common "why does my controller
keep crash-looping/logging errors" causes in real clusters, and the fix
is almost never "grant more" reflexively — it's reading the exact
`Forbidden` message and granting precisely what's missing.

## Prerequisites
- Docker installed and running
- `kind` and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates a single-node `k8s15` kind cluster, a ServiceAccount named
`deploy-bot`, and a Pod running under that ServiceAccount whose only job
is to call the API server directly every 5 seconds (`curl` plus its own
mounted token — no `kubectl` binary needed) trying to list Deployments in
`default` — no `Role` or `RoleBinding` exists for it yet.

## Step 2 — Confirm the incident
```bash
kubectl --context kind-k8s15 logs deploy-bot --since=6s
```
Every attempt fails the same way — this is the API server's own raw
response, the same thing `kubectl` itself would format and print:
```json
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "deployments.apps is forbidden: User \"system:serviceaccount:default:deploy-bot\" cannot list resource \"deployments\" in API group \"apps\" in the namespace \"default\"",
  "reason": "Forbidden",
  "details": { "group": "apps", "kind": "deployments" },
  "code": 403
}
```
The `message` field is the whole diagnosis in one line: which identity,
which verb, which resource, which namespace. There's nothing else to
guess.

## Step 3 — Confirm it from the authorizer's own point of view
```bash
kubectl --context kind-k8s15 auth can-i list deployments \
  --as=system:serviceaccount:default:deploy-bot -n default
```
`no` — `auth can-i --as` asks the exact same question the API server's
authorizer asks internally, without needing a running Pod to prove it.

## Step 4 — Fix it: grant exactly what's missing
```bash
kubectl --context kind-k8s15 create role deploy-reader \
  --verb=get,list,watch --resource=deployments -n default
kubectl --context kind-k8s15 create rolebinding deploy-bot-binding \
  --role=deploy-reader --serviceaccount=default:deploy-bot -n default
```

## Step 5 — Verify
```bash
./check.sh
```
Confirms `auth can-i` now says `yes`, and that `deploy-bot`'s own recent
logs no longer show `Forbidden`.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a RoleBinding that looks right but grants nothing:**
```bash
./reset.sh
kubectl --context kind-k8s15 create role deploy-reader-typo \
  --verb=get,list,watch --resource=deployments -n default
cat <<'EOF' | kubectl --context kind-k8s15 apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: deploy-bot-binding
  namespace: default
subjects:
  - kind: ServiceAccount
    name: deploy-bot
    namespace: default
roleRef:
  kind: Role
  name: deploy-reader
  apiGroup: rbac.authorization.k8s.io
EOF
kubectl --context kind-k8s15 get rolebinding deploy-bot-binding
sleep 8
kubectl --context kind-k8s15 logs deploy-bot --since=6s
```
The `RoleBinding` was created without any error, `kubectl get
rolebinding` shows it existing, everything *looks* wired up — and
`deploy-bot` is still Forbidden, now with an extra clue tacked onto the
`message` field it didn't have before. Compare the `Role` that was
actually created (`kubectl get role`) against what the `RoleBinding`'s
`roleRef` points at, and explain why the API server let this get created
at all instead of rejecting it up front.

**Challenge B — access works in one namespace but not another, same ClusterRole either way:**
```bash
./reset.sh
kubectl --context kind-k8s15 create clusterrole deploy-viewer --verb=get,list --resource=deployments
kubectl --context kind-k8s15 create rolebinding deploy-bot-binding \
  --clusterrole=deploy-viewer --serviceaccount=default:deploy-bot -n default
kubectl --context kind-k8s15 auth can-i list deployments --as=system:serviceaccount:default:deploy-bot -n default
kubectl --context kind-k8s15 auth can-i list deployments --as=system:serviceaccount:default:deploy-bot -n kube-system
```
`yes` in `default`, `no` in `kube-system` — despite binding a
`ClusterRole`, not a namespaced `Role`. If `deploy-bot` genuinely needs
to read Deployments across every namespace (not just `default`), what
single change fixes this — and what's the difference between what you
just did and what a `ClusterRoleBinding` would have done with the exact
same `ClusterRole`?

See `solution.md` only after you've formed your own diagnosis.
