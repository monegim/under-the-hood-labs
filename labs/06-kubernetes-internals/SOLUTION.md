# Lab 6 — Solutions

## Challenge A — Service with no endpoints

**Check:**
```bash
kubectl get endpoints nginx-svc
iptables-save | grep -A2 KUBE-SVC | grep -i nginx-svc
```
`kubectl get endpoints nginx-svc` shows no addresses (`<none>`). The `curl`
to the ClusterIP fails fast with "Connection refused," not a timeout.

**Diagnosis:** kube-proxy watches Endpoints/EndpointSlices and rewrites its
iptables rules whenever they change. With zero backing pods, there's no
`KUBE-SEP-...` (service endpoint) chain to DNAT into — kube-proxy replaces
what would have been the DNAT target with a `REJECT` rule instead of
leaving traffic to silently time out, specifically so clients fail fast
instead of hanging. This is one of the single most common real Kubernetes
incidents: a Service's label selector stops matching any Ready pod
(deployment scaled to zero, rollout failed, wrong selector, readiness probe
failing) and every client hitting that Service gets an instant, confusing
"connection refused" that looks like a firewall problem but is actually
"no endpoints."

**Fix:**
```bash
kubectl run nginx --image=nginx --restart=Never
kubectl wait --for=condition=Ready pod/nginx --timeout=60s
kubectl get endpoints nginx-svc
```
Get a Ready pod matching the Service's selector back, and kube-proxy
reconciles the rules automatically.

**Lesson:** "connection refused" against a ClusterIP almost always means
"no Ready endpoints," not "network is broken" — `kubectl get endpoints` is
the first command to run, before touching iptables, DNS, or CNI.

---

## Challenge B — pod reports Running but has no network

**Check:**
```bash
kubectl get pod nginx
kubectl describe pod nginx | grep -A5 Conditions
```
`kubectl get pod` still shows `1/1 Running` and `Ready`. The `curl` from
outside hangs or fails, even though Kubernetes' own status says everything
is fine.

**Diagnosis:** kubelet's readiness/liveness reporting is based on whatever
probes are CONFIGURED for the pod (by default, none beyond "container
process is alive") — it has no built-in check for "is this pod's network
interface actually up." Manually taking `eth0` down inside the pod's
network namespace doesn't touch the container process at all (nginx is
still running fine from the container runtime's point of view), so
kubelet has nothing that would flip readiness to false. This mirrors a
real, nasty class of production incidents: a CNI plugin bug, a half-applied
network policy, or manual intervention leaves a pod's network in a broken
state while every Kubernetes-level signal (`Running`, `Ready`, restart
count) says the pod is healthy.

**Fix:**
```bash
docker exec lab6-control-plane bash -c 'nsenter -t <pid> -n ip link set eth0 up'
```
Bring the interface back up; connectivity resumes without kubelet or the
container ever needing a restart.

**Lesson:** `kubectl get pod` reporting `Running`/`Ready` only reflects what
kubelet's configured probes check — it is not proof of network health.
Application-level readiness probes that actually exercise the network path
(not just "is the process alive") are the only way Kubernetes' own status
can catch this class of failure.
