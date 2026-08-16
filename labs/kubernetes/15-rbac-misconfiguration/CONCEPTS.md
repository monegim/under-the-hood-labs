# Lab 15 — Concept: RBAC Is Additive, Resolved Per-Request

## What's actually going on

Every request that reaches the Kubernetes API server carries an
identity — for in-cluster clients, almost always a `ServiceAccount`,
presented as a bearer token that the API server authenticates into a
username like `system:serviceaccount:<namespace>:<name>` and a set of
groups. Authentication only answers "who is this"; a completely separate
stage, authorization, answers "is this identity allowed to do this
specific verb on this specific resource." RBAC is the authorization mode
almost every cluster runs, and its entire model is a union: the API
server gathers every `Role`/`ClusterRole` rule reachable through every
`RoleBinding`/`ClusterRoleBinding` that names this identity (directly, or
via a group it belongs to), and the request is allowed if *any* rule
anywhere in that union matches. There is no "deny" rule in RBAC — the
only way to restrict access is to not grant it, which is why an
over-broad binding elsewhere (a wildcard `ClusterRoleBinding`, an
accidental group membership) can silently defeat an otherwise-correct
narrow `Role`.

Two separate axes decide the shape of a grant, and conflating them is
the root of both challenges here. The first axis is *what rules can be
expressed*: a `Role`'s rules only ever apply within the single namespace
that `Role` itself lives in; a `ClusterRole`'s rules can describe access
to cluster-scoped resource types (`Node`, `PersistentVolume`,
`Namespace` itself) that a `Role` fundamentally cannot reference
meaningfully, and a `ClusterRole` can also be reused across many
bindings rather than duplicated per namespace. The second, independent
axis is *how broadly a given binding applies*: a `RoleBinding` is itself
a namespaced object, and grants whatever its `roleRef` describes only
within the one namespace the `RoleBinding` lives in — even when that
`roleRef` points at a `ClusterRole`. A `ClusterRoleBinding` is
cluster-scoped and applies everywhere. Four real combinations exist
(`Role`+`RoleBinding`, `ClusterRole`+`RoleBinding`,
`ClusterRole`+`ClusterRoleBinding` — `Role`+`ClusterRoleBinding` isn't
possible, since a `ClusterRoleBinding`'s `roleRef` can only name a
`ClusterRole`), and "which role type" and "which binding type" have to
both be reasoned about, not just one.

`roleRef` itself is deliberately loose: the API server accepts a
`RoleBinding`/`ClusterRoleBinding` whose `roleRef` names a `Role`/
`ClusterRole` that doesn't exist, because the field is immutable once
set (no updating a binding to point somewhere else — you delete and
recreate it) and resolving it eagerly at creation time would add an
ordering dependency that gains nothing: the authorizer already has to
re-resolve `roleRef` on every single request anyway, since the target
`Role`'s rules can change independently after the binding was created.
A dangling `roleRef` isn't a special error state — it's functionally
identical to a binding that resolves to a `Role` with zero rules.

## Where this shows up in the real world

Any controller, operator, or CI/CD automation that talks to the
Kubernetes API is one YAML typo away from crash-looping on `Forbidden`
the moment it needs one more permission than it was granted — Helm
charts and operator installers that ship their own `Role`/`RoleBinding`
manifests are a frequent source of exactly this, especially after an
upgrade adds a new resource type the automation now touches but the
shipped RBAC manifests weren't updated for. The `Role` vs. `ClusterRole`
/ `RoleBinding` vs. `ClusterRoleBinding` distinction is the other
recurring source of incidents in the opposite direction: someone reaches
for a `ClusterRoleBinding` "just to make the error go away," and grants
an automation account far broader access than it needed, cluster-wide,
because that fixed the immediate symptom faster than reasoning through
which single namespace actually needed it.

## Go deeper

- **Website/docs:** Kubernetes docs, Using RBAC Authorization — https://kubernetes.io/docs/reference/access-authn-authz/rbac/ — the authoritative reference for `Role`/`ClusterRole`/`RoleBinding`/`ClusterRoleBinding` semantics, including the cluster-scoped-resource caveat.
- **Website/docs:** Kubernetes docs, `kubectl auth can-i` — https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth_can-i/ — the exact tool for asking the authorizer's own question directly, without needing a running workload to prove it.
- **Website/docs:** Kubernetes docs, Authenticating (Service Account Tokens) — https://kubernetes.io/docs/reference/access-authn-authz/authentication/#service-account-tokens — how a Pod's mounted token becomes the `system:serviceaccount:<ns>:<name>` identity RBAC rules match against.
- **Book:** *Kubernetes in Action* — Marko Lukša — covers RBAC's additive model and the Role/ClusterRole distinction in depth, alongside real troubleshooting framing.
- **Blog:** learnk8s, "A visual guide to Kubernetes RBAC" — https://learnk8s.io/rbac-kubernetes — a diagram-driven walkthrough of exactly how Roles, RoleBindings, and their cluster-scoped counterparts compose.
