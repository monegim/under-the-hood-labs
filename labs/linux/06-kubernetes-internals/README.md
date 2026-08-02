# Lab 6 — Kubernetes Internals

## Objective
Demystify what kubelet, the CNI plugin, and kube-proxy actually do
mechanically — using the exact primitives from Labs 1–5. Prove that a
pod's network namespace is just a namespace you can `nsenter` into, and
that a Kubernetes Service is just iptables DNAT rules.

## Why this matters
"Pod" and "Service" stop being magic the moment you see that a pod's
network is a namespace (Lab 1), a "node" here is just a container sharing
the host kernel (Lab 4's whole premise), and kube-proxy's job is generating
the same kind of NAT rules you could write by hand. This is the single
biggest unlock for debugging real cluster networking issues instead of
guessing.

## Prerequisites
- Docker installed and running
- `kind` (Kubernetes in Docker) and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```
Install if missing (check https://github.com/kubernetes-sigs/kind/releases
for the current latest tag — this lab was written against v0.23.0):
```bash
KIND_VERSION=v0.23.0
curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

## Step 1 — Create a cluster and look at what "node" means
```bash
kind create cluster --name lab6
kubectl get nodes
docker ps --filter "name=lab6"
```
> Gotcha: a kind "node" is just a Docker container running its own
> systemd/containerd/kubelet stack — it shares your host's kernel, same as
> every other container you've built in this series. There is no separate
> VM per node.

## Step 2 — Deploy a pod and a Service
```bash
kubectl run nginx --image=nginx --restart=Never
kubectl wait --for=condition=Ready pod/nginx --timeout=60s
kubectl expose pod nginx --port=80 --name=nginx-svc
kubectl get pod nginx -o wide
kubectl get svc nginx-svc
```

## Step 3 — Find the pod's network namespace and nsenter into it
Everything below runs from inside the kind node container, since that's
where containerd/crictl actually manage the pod:
```bash
docker exec -it lab6-control-plane bash
crictl pods
```
Find the sandbox ID for `nginx`, then:
```bash
crictl inspectp <sandbox-id> | grep -i pid
nsenter -t <pid> -n ip addr
nsenter -t <pid> -n ip route
```
That's the pod's actual network namespace — the same `veth`-plus-namespace
pattern from Lab 1, just wired up automatically by the CNI plugin instead
of by hand. `nsenter -t <pid> -n` is conceptually identical to what
`kubectl exec` and CNI plugins do internally via `setns()`.

## Step 4 — Read kube-proxy's actual rules
Still inside the node container:
```bash
iptables-save | grep -A2 KUBE-SERVICES
iptables-save | grep nginx-svc
```
(kind defaults to iptables mode for kube-proxy; if your cluster uses IPVS
instead, check `ipvsadm -Ln` for equivalent rules.) You should see a
`KUBE-SVC-...` chain matching the Service's ClusterIP, and a
`KUBE-SEP-...` chain doing DNAT to the pod's actual IP — kube-proxy did not
invent new mechanism here, it's the same `iptables` you'd write by hand for
port forwarding.

## Step 5 — Clean up
```bash
exit
kind delete cluster --name lab6
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — Service with no endpoints:**
```bash
kubectl delete pod nginx
kubectl get endpoints nginx-svc
docker exec lab6-control-plane curl -m 3 http://<nginx-svc-clusterIP>
```
Get the ClusterIP from `kubectl get svc nginx-svc`. Figure out exactly why
the connection fails the way it does (not a hang, not a normal refusal to
resolve DNS — look at `iptables-save` again and compare to Step 4), and
what real-world Kubernetes misconfiguration this simulates.

**Challenge B — pod reports Running but has no network:**
Recreate the pod, wait for it to be Ready, then find its network
namespace's PID again (Step 3) and:
```bash
docker exec lab6-control-plane bash -c 'nsenter -t <pid> -n ip link set eth0 down'
kubectl get pod nginx
docker exec lab6-control-plane curl -m 3 http://<nginx-svc-clusterIP>
```
Compare what `kubectl get pod` reports to what actually happens when you
try to reach it. This is a real CNI-plugin-failure/bad-network-state
scenario — figure out why Kubernetes' own status reporting doesn't catch
this.

See `SOLUTION.md` only after you've formed your own diagnosis.
