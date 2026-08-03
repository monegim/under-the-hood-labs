# Lab 8 — Concept: An Ingress Is Just Config a Controller Chooses to Read

## What's actually going on

An `Ingress` object, on its own, does nothing — it's inert configuration
sitting in etcd until some ingress controller (ingress-nginx in this lab,
but the same is true of any implementation) notices it, matches it
against its own `IngressClass`, and translates it into actual routing
config for whatever proxy the controller runs (an internal nginx config
reload, in ingress-nginx's case). This lab installs ingress-nginx using
kind's own documented recipe: a kind cluster config with
`extraPortMappings` forwarding host ports 80/443 into the node container,
and a `kubeadmConfigPatches`-applied node label (`ingress-ready=true`)
that ingress-nginx's kind-specific manifest uses as a node selector, so
the controller's pod actually lands on a node whose ports are exposed to
your host. None of that setup logic is specific to "fixing an incident" —
it's just the mechanical prerequisite for an Ingress to be reachable at
all in a local kind cluster.

Once traffic reaches the controller, matching an `Ingress` rule to an
actual backend is a two-step lookup: find the named Service, then find
the named (or numbered) port on that Service. Step 3-4's failure (a
backend Service that doesn't exist) and Challenge A's failure (a Service
that exists but doesn't expose the requested port) fail at these two
different steps, which is exactly why ingress-nginx's own log lines
distinguish them — "service not found" versus a port-lookup error
specifically. Both produce the same client-visible symptom (a `503` from
the controller's own fallback handling, since it has a route rule but no
usable backend for it), which is why the controller's logs, not just
`kubectl describe ingress`, are the reliable second check once you've
confirmed the Ingress object itself exists and looks superficially fine.

`IngressClass` matching (Challenge B) happens at a completely different,
earlier stage: before a controller does anything with an Ingress's
rules/backends at all, it first checks whether that Ingress's
`spec.ingressClassName` names an `IngressClass` this controller owns
(each `IngressClass` object typically has a `spec.controller` field
identifying which controller implementation it belongs to — ingress-nginx
watches for `IngressClass`es whose controller is
`k8s.io/ingress-nginx`). An Ingress with no matching class, whether from
a typo, an omitted field on a cluster running multiple ingress
controllers, or referencing a controller that was never installed, is
filtered out of that controller's watch entirely — it's not that the
controller looked at it and rejected it, it's that the object never
enters the controller's processing logic at all. This is why Challenge
B produces zero signal anywhere the earlier failures produced at least
some: there's no "attempted and failed" log line to find, because
nothing was attempted.

## Where this shows up in the real world

Wrong backend Service names/ports are an extremely common typo/copy-paste
error, especially across environments where a Service name changes
between a template and its instantiation (Helm values files referencing
a stale service name after a rename, multi-environment overlays with
inconsistent naming). IngressClass mismatches have become more common
specifically *because* the mechanism changed — clusters upgraded from
the older `kubernetes.io/ingress.class` annotation convention sometimes
have Ingress manifests still using the old annotation with no
`ingressClassName` set at all, which silently stops being read by
current ingress-nginx versions; multi-tenant clusters running more than
one ingress controller (a common real setup — an internal-only
controller alongside a public-facing one) see this constantly when an
Ingress is deployed with no class specified and simply vanishes from
routing without any error, because "no class matches" and "the wrong
controller's class matches" are both silent from the perspective of the
controller you expected to pick it up.

## Go deeper

- **Website/docs:** kind docs — https://kind.sigs.k8s.io/docs/user/ingress/ — kind's own guide to setting up ingress support, including the `extraPortMappings`/node-label pattern this lab uses.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/concepts/services-networking/ingress/ — the authoritative reference for Ingress objects, `IngressClass`, and backend resolution.
- **Website/docs:** ingress-nginx docs — https://kubernetes.github.io/ingress-nginx/ — the controller-specific documentation for the exact component this lab installs and debugs.
- **Website/docs:** Kubernetes docs — https://kubernetes.io/docs/tasks/debug/ — general troubleshooting task index this lab's diagnostic sequence follows.
- **YouTube:** That DevOps Guy (Marcel Dempers) — https://www.youtube.com/@MarcelDempers — hands-on ingress-nginx and Kubernetes Ingress troubleshooting videos.
