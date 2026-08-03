# Lab 3 — Solutions

## Challenge A — approaching the quota vs. actually hitting it

**Check:**
```bash
ETCD_POD=$(kubectl --context kind-k8s03 -n kube-system get pods -l component=etcd -o jsonpath='{.items[0].metadata.name}')
kubectl --context kind-k8s03 -n kube-system exec "$ETCD_POD" -- \
  etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint status --write-out=table
kubectl --context kind-k8s03 -n kube-system exec "$ETCD_POD" -- \
  etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
    alarm list
```
`endpoint status` shows `DB SIZE` close to but under 16MiB, and
`alarm list` returns nothing — no alarm is active, so by definition
nothing is being rejected on quota grounds yet.

**Diagnosis:** the quota check happens per-write, against the backend
size *at the moment of that write*, not against some averaged or
predicted trend. There's no "getting close" state that etcd exposes as a
warning — you're either under quota (writes succeed normally) or you've
crossed it (the alarm fires and every subsequent write is rejected until
disarmed). If your loop happened to succeed 40/40 times, the combined
size of the junk ConfigMaps you added just hadn't pushed the backend past
16MiB yet; run a few more iterations, or check `endpoint status` first to
see how much room is actually left, then compute how much more data you'd
need to add.

**Fix:** not a fix — this challenge is a diagnostic exercise. To actually
reproduce the NOSPACE condition, keep adding data (or check `DB SIZE`
against the quota first and size your test data accordingly) until
`alarm list` shows `NOSPACE`.

**Lesson:** `endpoint status`'s `DB SIZE` field is the only way to know
how much headroom is actually left — don't infer proximity to the quota
from "how much lab data I've created," infer it from etcd's own reported
size. And once the alarm does fire, every write fails identically and
immediately; there's no partial-degradation state to catch in between.

---

## Challenge B — compact shrinks logical history, not the file on disk

**Check:**
```bash
ETCD_POD=$(kubectl --context kind-k8s03 -n kube-system get pods -l component=etcd -o jsonpath='{.items[0].metadata.name}')
ETCDCTL="kubectl --context kind-k8s03 -n kube-system exec $ETCD_POD -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
$ETCDCTL endpoint status --write-out=table   # DB SIZE before
$ETCDCTL defrag
$ETCDCTL endpoint status --write-out=table   # DB SIZE after
```
`DB SIZE` barely changes (or doesn't change at all) right after
`compact`, even though compact reported success. It only drops
noticeably after `defrag` runs.

**Diagnosis:** `compact` only tells etcd's MVCC layer "you may now
discard old key revisions older than this one" — it's a logical
operation on which historical versions are still reachable. It does
**not** shrink the actual `db` file on disk; the space freed up by
discarding old revisions becomes free pages *inside* the existing bolt
database file, available for reuse by future writes, but the file itself
stays the same size on disk (and so does `DB SIZE` as etcd reports it,
since that reflects the backend file's allocated size, not live data
size). `defrag` is the operation that actually rewrites the backend file
to reclaim that freed space and shrink `DB SIZE` for real — which is why
skipping it leaves you back at "NOSPACE" even after a successful
compact.

**Fix:**
```bash
$ETCDCTL defrag
$ETCDCTL alarm disarm
```

**Lesson:** `compact` and `defrag` do genuinely different jobs and both
are required to actually recover disk headroom — compact without defrag
looks like it worked (no error) but leaves `DB SIZE` unchanged, which is
exactly why real incident runbooks always list them as two separate,
sequential steps, never one or the other. In production, also never
`defrag` all etcd members at once — do it one member at a time, since a
member is briefly unavailable while defragmenting and a multi-member
cluster could lose quorum if defragged in parallel (not a concern in this
single-node kind lab, but critical in a real HA etcd cluster).
