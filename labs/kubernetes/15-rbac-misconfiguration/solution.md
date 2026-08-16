# Lab 15 — Solutions

## Challenge A — a RoleBinding that looks right but grants nothing

**Check:**
```bash
kubectl --context kind-k8s15 get role
kubectl --context kind-k8s15 get rolebinding deploy-bot-binding -o yaml | grep -A3 roleRef
kubectl --context kind-k8s15 logs deploy-bot --since=6s
```
`get role` lists `deploy-reader-typo` — there is no `Role` named
`deploy-reader` anywhere in the namespace. The `RoleBinding`'s `roleRef`
points at `deploy-reader`, which simply doesn't exist. The Pod's own
logs now show a more specific `message` than the main lab did:
`"...RBAC: role.rbac.authorization.k8s.io \"deploy-reader\" not found"` —
the API server is naming the exact missing object.

**Diagnosis:** `RoleBinding.roleRef` is not validated against the
existence of the named `Role` at creation time — the API server accepts
a `RoleBinding` referencing a `Role` that doesn't exist (yet, or ever),
because `roleRef` is immutable once set and there's no ordering
requirement forcing the `Role` to exist first. The authorizer only
resolves `roleRef` at *authorization-check* time, for every single
request — and when it can't find the referenced `Role`, it simply
contributes no permissions from that binding, the same as if the binding
didn't exist. `kubectl auth can-i` and the Pod's own logs both show
`Forbidden`, with no error anywhere pointing at the typo itself.

**Fix:**
```bash
kubectl --context kind-k8s15 create role deploy-reader \
  --verb=get,list,watch --resource=deployments -n default
```
(or correct the `RoleBinding`'s `roleRef.name` to match the `Role` that
actually exists — either resolves it, since `roleRef` just needs to
point at *something* real).

**Lesson:** a `RoleBinding` existing is not evidence that it's granting
anything. Always cross-check `roleRef.name`/`roleRef.kind` against
`kubectl get role`/`kubectl get clusterrole` output directly — a typo in
either the `Role`'s name or the `RoleBinding`'s reference to it produces
the exact same symptom (silent, total denial) as never creating the
`RoleBinding` at all.

---

## Challenge B — access works in one namespace but not another, same ClusterRole either way

**Check:**
```bash
kubectl --context kind-k8s15 get rolebinding deploy-bot-binding -n default -o yaml | grep -A3 roleRef
```
`kind: ClusterRole`, `name: deploy-viewer` — confirms a `ClusterRole` is
what's referenced, yet access is still namespace-scoped in practice.

**Diagnosis:** what a binding references (`Role` vs. `ClusterRole`)
controls *what rules are available to grant* — a `ClusterRole`'s rules
can describe access to both namespaced and cluster-scoped resource
types. But *where the binding itself lives* is what controls how broadly
those rules actually apply: a `RoleBinding` is a namespaced object, and
no matter what it references, the permission it grants is scoped to
exactly the one namespace the `RoleBinding` itself is created in. Binding
`deploy-viewer` via a `RoleBinding` in `default` grants `deploy-bot`
those permissions *only inside `default`* — the `ClusterRole` supplied
the rule content, the `RoleBinding` capped its reach.

**Fix:**
```bash
kubectl --context kind-k8s15 delete rolebinding deploy-bot-binding -n default
kubectl --context kind-k8s15 create clusterrolebinding deploy-bot-binding \
  --clusterrole=deploy-viewer --serviceaccount=default:deploy-bot
kubectl --context kind-k8s15 auth can-i list deployments --as=system:serviceaccount:default:deploy-bot -n kube-system
```
A `ClusterRoleBinding` is itself cluster-scoped (not namespaced), so
binding the exact same `ClusterRole` through one instead grants the
permission everywhere, all namespaces included.

**Lesson:** `Role` vs. `ClusterRole` and `RoleBinding` vs.
`ClusterRoleBinding` are two independent decisions, not one — reusing a
single `ClusterRole` via a `RoleBinding` per namespace is actually a
legitimate, common pattern for granting the *same* permission set
namespace-by-namespace without duplicating `Role` objects; reaching for
a `ClusterRoleBinding` is the deliberate choice for "everywhere, no
exceptions." Picking the wrong one either under-grants (Challenge B, as
seen) or over-grants far more broadly than intended — always check which
of the two binding kinds is in use, not just which role it names.
