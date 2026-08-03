# Lab 9 — Solutions

## Challenge A — a certificate-loading failure instead of a connection failure

**Check:**
```bash
docker exec k8s09-control-plane bash -c "crictl logs \$(crictl ps -a --name kube-apiserver -q | head -1) 2>&1 | tail -20"
```
The log now shows something like `unable to load client CA file
/etc/kubernetes/pki/does-not-exist.crt: no such file or directory` — a
startup/config-loading failure, not a network connection error.

**Diagnosis:** Step 3's failure (wrong etcd port) happens *after* the API
server successfully starts and tries to actually reach etcd over the
network — the process comes up, then fails at runtime trying to connect.
This challenge's failure happens *before* the process can even finish
initializing — it can't load a required file off disk at all, which is
a fundamentally earlier failure stage. Both produce an identically
crash-looping container and an identically unreachable `kubectl`, but
the log text tells you immediately whether you're looking for a
networking problem (can this process reach something else) or a
filesystem/config problem (does this process have everything it needs
just to start).

**Fix:**
```bash
docker exec k8s09-control-plane bash -c "
  sed -i 's#--etcd-cafile=/etc/kubernetes/pki/does-not-exist.crt#--etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt#' /etc/kubernetes/manifests/kube-apiserver.yaml
"
sleep 15
kubectl --context kind-k8s09 get nodes
```

**Lesson:** "container is crash-looping" is never the full diagnosis by
itself — always read the actual log line from the crashed container
(`crictl logs`, working entirely at the node level, no API server
required) before assuming you know why. A connection-refused-style error
and a file-not-found-style error both crash the same container the same
way, but point at completely different fixes.

---

## Challenge B — the node itself is unreachable, not just one static pod

**Check:**
```bash
docker ps -a --filter "name=k8s09-control-plane"
docker exec -it k8s09-control-plane bash
```
`docker ps -a` shows the container as `Exited`, not `Up`. `docker exec`
into a stopped container fails outright — there is no running process
namespace to exec into.

**Diagnosis:** Steps 1-4 and Challenge A both left the node container
itself running the whole time — only one static pod (the API server) was
broken, which is why `docker exec` + `crictl` + `journalctl` all kept
working and gave you a full diagnostic trail with zero dependence on
`kubectl`. Stopping the container entirely removes that entire toolkit at
once: there's no init process, no containerd, no kubelet, nothing to
exec into or query, until the container itself starts again. This is a
categorically worse situation — not "one component on a healthy node is
broken" but "the node doesn't exist right now as far as anything is
concerned."

**Fix:**
```bash
docker start k8s09-control-plane
sleep 20
kubectl --context kind-k8s09 get nodes
```

**Lesson:** "I can't run any diagnostics at all, not even locally" is
itself diagnostic information — it tells you the failure is at the
node/host level (the machine is off, unreachable over the network, or the
container/VM is stopped), not at the level of any single component
running on it. In a real incident, this maps to a control-plane node
that's fully down (hardware failure, the VM/instance itself stopped, a
total network partition to that host) — the response there isn't "SSH in
and check logs," it's "get the node back (reboot, restart the instance,
fix the network path) before any component-level diagnosis is even
possible," which is exactly what `docker start` stands in for here.
