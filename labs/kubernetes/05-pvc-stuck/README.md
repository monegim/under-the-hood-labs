# Lab 5 — PVC Stuck (No Matching StorageClass, and a Released PV Trap)

## Objective
Get a `PersistentVolumeClaim` stuck in `Pending` two different ways — a
`storageClassName` that doesn't exist, and a `Retain`-policy `PersistentVolume`
left in `Released` state blocking reuse — and learn to read
`kubectl describe pvc`'s events instead of guessing.

## Why this matters
"My pod won't start, it's stuck in `Pending`/`ContainerCreating`" is one
of the most common tickets an on-call engineer sees, and a huge fraction
of the time the actual blocker is a step removed from the pod entirely:
its PVC never bound. Kubernetes' storage provisioning has several
distinct ways to silently produce "nothing happens, forever" instead of a
clear error — a typo'd `storageClassName`, a manually-created PV that
looks like it should be reusable but isn't — and `kubectl describe pvc`'s
Events section is almost always where the real answer is sitting, even
though the pod's own events just say `FailedMount` or nothing at all.

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
kind create cluster --name k8s05
```
(kind ships a default `StorageClass` called `standard`, backed by
Rancher's `local-path-provisioner`, which is what makes dynamic
provisioning work out of the box here — no extra CSI driver install
needed for this lab.)

## Step 1 — Run setup.sh
```bash
bash setup.sh
```
This creates the `k8s05` kind cluster, confirms the default `standard`
StorageClass provisions normally (baseline PVC that binds fine), then
creates a second PVC, `data-pvc`, requesting `storageClassName: fast-ssd`
— a StorageClass that doesn't exist anywhere in the cluster.

## Step 2 — Confirm the symptom
```bash
kubectl --context kind-k8s05 get pvc data-pvc
```
`STATUS` is `Pending` and stays that way indefinitely — no error, no
retry-and-fail, just permanently `Pending`.

## Step 3 — Read the actual event
```bash
kubectl --context kind-k8s05 describe pvc data-pvc
```
The `Events` section shows something like
`waiting for a volume to be created, either by external provisioner
"rancher.io/local-path" or manually by the system administrator` — but
critically, check which provisioner is even being asked:
```bash
kubectl --context kind-k8s05 get storageclass
kubectl --context kind-k8s05 get pvc data-pvc -o jsonpath='{.spec.storageClassName}{"\n"}'
```
`get storageclass` lists `standard` — there's no `fast-ssd` at all. The
PVC is waiting on a provisioner that was never going to show up.

## Step 4 — Fix it: point the PVC at a StorageClass that exists
PVCs' `storageClassName` is immutable once bound, but this one never
bound, so it can be edited directly:
```bash
kubectl --context kind-k8s05 patch pvc data-pvc -p '{"spec":{"storageClassName":"standard"}}'
kubectl --context kind-k8s05 get pvc data-pvc -w
```
(Ctrl+C once `STATUS` flips to `Bound`.) In a real cluster the more
common fix is the other direction — create the `fast-ssd` StorageClass
the PVC was actually supposed to use — but either direction proves the
same thing: the PVC was never broken, it was just referencing something
that didn't exist.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a Retain-policy PV stuck Released, blocking reuse:**
```bash
bash -c '
CTX=kind-k8s05
cat <<EOF | kubectl --context $CTX apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: manual-pv
spec:
  capacity:
    storage: 1Gi
  accessModes: ["ReadWriteOnce"]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /tmp/lab5-manual-pv
EOF
cat <<EOF | kubectl --context $CTX apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: manual-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  resources:
    requests:
      storage: 1Gi
EOF
kubectl --context $CTX wait --for=jsonpath="{.status.phase}"=Bound pvc/manual-pvc --timeout=30s
kubectl --context $CTX delete pvc manual-pvc
kubectl --context $CTX get pv manual-pv
cat <<EOF | kubectl --context $CTX apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: manual-pvc-2
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  resources:
    requests:
      storage: 1Gi
EOF
kubectl --context $CTX get pvc manual-pvc-2
'
```
`manual-pv` is now `Released`, not `Available`, and `manual-pvc-2` is
stuck `Pending` even though a PV of the right size/class technically
exists. Explain exactly why Kubernetes won't just hand `manual-pv` to the
new claim, and what `kubectl get pv manual-pv -o yaml`'s `claimRef` field
has to do with it.

**Challenge B — capacity mismatch on statically-provisioned storage:**
```bash
bash -c '
CTX=kind-k8s05
cat <<EOF | kubectl --context $CTX apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: small-pv
spec:
  capacity:
    storage: 500Mi
  accessModes: ["ReadWriteOnce"]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /tmp/lab5-small-pv
EOF
cat <<EOF | kubectl --context $CTX apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: big-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  resources:
    requests:
      storage: 5Gi
EOF
kubectl --context $CTX get pvc big-pvc
kubectl --context $CTX get pv
'
```
`big-pvc` stays `Pending` even though `manual-pv`/`small-pv`-class PVs
exist for `storageClassName: manual`. Figure out exactly which field
Kubernetes is comparing here, and why "a PV exists with this
StorageClass" isn't sufficient for a bind to happen.

See `solution.md` only after you've formed your own diagnosis.
