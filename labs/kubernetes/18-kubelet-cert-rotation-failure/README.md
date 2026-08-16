# Lab 18 — Kubelet Client Certificate Rotation Failure

## Objective
Break the certificate kubelet uses to authenticate *itself to the API
server* (not the API server's own cert, not an admission webhook's) so
the node the kubelet is running on goes `NotReady` from the cluster's
point of view, while the node and kubelet process are both still
completely alive underneath. Learn to tell this apart from both a
genuinely dead node and from `09-api-server-unavailable` — here the API
server is perfectly healthy and answers `kubectl` normally; it's just
one node's kubelet that it no longer trusts.

## Why this matters
`NotReady` is usually read as "something is wrong with the node" in a
generic, physical sense — out of resources, kubelet crashed, the machine
is unreachable. A kubelet client certificate problem produces the exact
same top-level symptom (`NotReady`) for a completely different reason:
the node is fine, kubelet is fine, and it's still actively trying to
report in — it just can't authenticate anymore, so the API server never
hears from it and eventually gives up waiting and marks it `Unknown`.
Every kubeadm-based cluster (which includes every kind cluster) rotates
this specific certificate automatically in the background, and it's easy
to assume "automatic" means "can't fail." It can: a node whose clock
drifts, a botched manual cert regeneration, or kubelet being down across
a rotation window can all leave a node with a client cert the API server
won't accept anymore — and because the failure is entirely about
authentication, `kubectl` (which talks to the API server, not the node)
tells you almost nothing useful about *why*. The node itself is where
the real answer lives.

## Prerequisites
- Docker installed and running
- `kind` and `kubectl`

Check first:
```bash
docker version
kind version 2>/dev/null || echo "kind not installed"
kubectl version --client 2>/dev/null || echo "kubectl not installed"
```

Cluster creation (this is what `setup.sh` runs for you):
```bash
kind create cluster --name k8s18
```

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s18` kind cluster, confirms the node starts `Ready`,
then on the control-plane node generates a brand new client certificate
- signed by the cluster's real CA, so it *looks* legitimate - but with
`-days -1`, meaning it's already expired the moment it's created. It
replaces `/var/lib/kubelet/pki/kubelet-client-current.pem` (the symlink
kubelet's automatic rotation keeps pointed at its current valid cert)
with this expired one and restarts kubelet.

> **Design note:** this depends on kubeadm's default kubelet client-cert
> rotation layout (`--rotate-certificates` enabled, certs tracked as
> timestamped files under `/var/lib/kubelet/pki/` with
> `kubelet-client-current.pem` symlinked to whichever one is active).
> This is standard kubeadm behavior and kind clusters are
> kubeadm-bootstrapped, but if your local kind/kubeadm version ever lays
> this out differently, `setup.sh` checks for the symlink up front and
> fails loudly rather than silently doing the wrong thing.

## Step 2 — Confirm the symptom
```bash
kubectl --context kind-k8s18 get nodes
```
The node shows `NotReady` (or flips to `Unknown` conditions shortly
after). Note that this command itself still works fine — unlike Lab 9,
the API server is completely healthy and answering normally.

## Step 3 — Read the node's conditions
```bash
kubectl --context kind-k8s18 describe node k8s18-control-plane | grep -A5 Conditions
```
Look for `Ready` with status `Unknown` and a reason/message like
`NodeStatusUnknown` / `Kubelet stopped posting node status`. This is the
API server's own description of what it's observing: not "the node told
me it's broken," but "the node stopped telling me anything at all."
That distinction (a node reporting itself unhealthy vs. a node going
silent) is exactly what a cert-auth failure looks like from the
control plane's side.

## Step 4 — Diagnose at the node level
```bash
NODE=k8s18-control-plane
docker exec "${NODE}" journalctl -u kubelet --no-pager | tail -30
```
kubelet's own systemd-managed logs (independent of the API server, just
like in Lab 9's Step 4) show it repeatedly failing to talk to the API
server - look for something like `certificate has expired or is not yet
valid` or a TLS handshake error. Confirm it directly:
```bash
docker exec "${NODE}" bash -c '
  TARGET=$(readlink -f /var/lib/kubelet/pki/kubelet-client-current.pem)
  echo "current cert target: $TARGET"
  openssl x509 -in "$TARGET" -noout -enddate
'
```
The `notAfter` date is in the past. Compare this to Lab 9: there, the API
server itself was crash-looping and *nothing* worked, from any angle.
Here, `kubectl get pods -A` and everything else against the API server
works completely normally - it's specifically this one node's ability to
authenticate that's broken, which is a much narrower and easier-to-miss
class of failure.

## Step 5 — Fix it
The client cert rotation mechanism keeps every previously-issued cert
file on disk, it just repoints the symlink - so recovery here means
finding the last real one and pointing back to it:
```bash
NODE=k8s18-control-plane
docker exec "${NODE}" bash -c '
  ls -la /var/lib/kubelet/pki/kubelet-client-*.pem
  GOOD=$(ls -t /var/lib/kubelet/pki/kubelet-client-20*.pem 2>/dev/null | head -1)
  echo "relinking to: $GOOD"
  ln -sf "$GOOD" /var/lib/kubelet/pki/kubelet-client-current.pem
  systemctl restart kubelet
'
sleep 20
kubectl --context kind-k8s18 get nodes
```
The node should return to `Ready`. (In a real incident where no
previously-good cert file still exists, the practical fix is usually
deleting the node object and letting it rejoin via a fresh bootstrap
token, or restarting kubelet with `--rotate-certificates` against a
still-valid bootstrap kubeconfig - both heavier operations than this lab
needs, but worth knowing this recovery path has a floor.)

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a cert that's still valid, but for the wrong identity:**
```bash
NODE=k8s18-control-plane
docker exec "${NODE}" bash -c '
  openssl genrsa -out /tmp/wrong-cn-client.key 2048 2>/dev/null
  openssl req -new -key /tmp/wrong-cn-client.key \
    -subj "/O=system:nodes/CN=system:node:some-other-node" \
    -out /tmp/wrong-cn-client.csr 2>/dev/null
  openssl x509 -req -in /tmp/wrong-cn-client.csr \
    -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial \
    -days 365 -out /tmp/wrong-cn-client.crt 2>/dev/null
  cat /tmp/wrong-cn-client.crt /tmp/wrong-cn-client.key > /var/lib/kubelet/pki/kubelet-client-wrongcn.pem
  ln -sf /var/lib/kubelet/pki/kubelet-client-wrongcn.pem /var/lib/kubelet/pki/kubelet-client-current.pem
  systemctl restart kubelet
'
sleep 20
kubectl --context kind-k8s18 get nodes
docker exec "${NODE}" journalctl -u kubelet --no-pager | tail -20
```
This cert is signed by the real CA and isn't expired - the TLS handshake
itself succeeds. Compare the kubelet log text here to Step 4's: this
time it's not a certificate-validity error at all, it's an authorization
error (`Forbidden`, `cannot get resource "nodes"`, or similar) - the
node authorizer specifically checks that the cert's identity
(`CN=system:node:<name>`) matches the node it's claiming to be, and
rejects a cert claiming to be a *different* node. Figure out why this is
a fundamentally different failure than an expired cert (hint: which
phase fails - the TLS handshake, or the request that comes after it?)
before fixing it the same way as Step 5.

**Challenge B — a cert signed by a CA the cluster doesn't trust at all:**
```bash
NODE=k8s18-control-plane
docker exec "${NODE}" bash -c '
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout /tmp/rogue-ca.key -out /tmp/rogue-ca.crt -subj "/CN=not-the-real-ca" 2>/dev/null
  openssl genrsa -out /tmp/rogue-client.key 2048 2>/dev/null
  openssl req -new -key /tmp/rogue-client.key \
    -subj "/O=system:nodes/CN=system:node:'"${NODE}"'" -out /tmp/rogue-client.csr 2>/dev/null
  openssl x509 -req -in /tmp/rogue-client.csr \
    -CA /tmp/rogue-ca.crt -CAkey /tmp/rogue-ca.key -CAcreateserial \
    -days 365 -out /tmp/rogue-client.crt 2>/dev/null
  cat /tmp/rogue-client.crt /tmp/rogue-client.key > /var/lib/kubelet/pki/kubelet-client-rogue.pem
  ln -sf /var/lib/kubelet/pki/kubelet-client-rogue.pem /var/lib/kubelet/pki/kubelet-client-current.pem
  systemctl restart kubelet
'
sleep 20
kubectl --context kind-k8s18 get nodes
docker exec "${NODE}" journalctl -u kubelet --no-pager | tail -20
```
Compare this log text to both Step 4 and Challenge A - this one fails
even earlier, during the TLS handshake itself, with something like
`certificate signed by unknown authority`. Line up all three failures
you've now seen (expired, wrong identity, wrong issuer) against which
phase of the connection they break: cert validity, cert trust chain, or
post-handshake authorization. Fix it the same way as Step 5.

See `solution.md` only after you've formed your own diagnosis.
