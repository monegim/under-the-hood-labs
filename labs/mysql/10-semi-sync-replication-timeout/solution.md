# Lab 10 — Solutions

## Challenge A — the timeout window is a real, if narrow, data-loss window

**Check:**
```bash
docker exec lab10-primary mysql -uroot -prootpass -e "SHOW MASTER STATUS\G"
docker exec lab10-replica mysql -uroot -prootpass appdb -e "SELECT * FROM orders ORDER BY id DESC LIMIT 3;"
```
Immediately after `docker unpause`, the replica's IO thread hasn't had a
chance to catch up yet — `'promoted-during-outage'` is momentarily absent
from the replica. A few seconds later (once `Seconds_Behind_Source` drains
back to 0), it's there.

**Diagnosis:** the row committed on the primary the moment
`rpl_semi_sync_source_timeout` expired — the primary gave up waiting for
an ACK and returned success to the client, exactly as designed. At that
exact instant, the ONLY durable copy of that row is on the primary. If the
primary had actually crashed in that window (instead of just having a
frozen replica), that row would be gone forever from the replica's
perspective — a promoted replica would never have seen it, and depending
on your failover tooling, might not even know it was supposed to exist.
This is precisely the gap semi-sync is designed to close, and precisely
the gap that reopens the moment a replica goes unreachable for longer than
the timeout: the "semi" in semi-sync means "best effort with a bailout,"
not "guaranteed, full stop."

**Fix:** there isn't a config fix for this scenario — it's the designed,
documented behavior. The actual fix is **operational**: alert on
`Rpl_semi_sync_source_status` transitioning to `OFF` (and on
`Rpl_semi_sync_source_no_tx` incrementing) as a first-class incident, not
a metric nobody looks at, specifically because writes that land during
that window carry a real, if usually brief, risk of loss on primary
failure. Some environments choose `rpl_semi_sync_source_wait_no_slave=OFF`
combined with requiring multiple replica ACKs instead of any one, trading
availability (more likely to stall on commits) for a tighter durability
window — a conscious trade-off, not a free fix.

**Lesson:** semi-sync's timeout-and-fallback design means "durability
guarantee" is actually "durability guarantee, except during a bounded
window while a replica is unresponsive, during which you silently have
none." Treat the OFF status as an active incident with a real blast
radius (every write since the fallback began), not a transient blip to
shrug off once the replica comes back.

---

## Challenge B — "any one replica ACKed" doesn't mean "this replica has it"

**Check:**
```bash
docker exec lab10-primary mysql -uroot -prootpass -e "SHOW STATUS LIKE 'Rpl_semi_sync_source_status';"
docker exec lab10-primary mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'rpl_semi_sync_source_wait_no_slave';"
```
With `rpl_semi_sync_replica2` frozen but the original `replica` still
healthy and ACKing, the write from Step "two-replica-test" commits fast —
no ~3s stall — and `Rpl_semi_sync_source_status` stays `ON` throughout.

**Diagnosis:** `rpl_semi_sync_source_wait_no_slave` defaults to `ON`,
meaning the primary is satisfied the instant **any** attached semi-sync
replica ACKs — it does not wait for all of them, and it doesn't track or
expose which specific replica(s) ACKed a given transaction versus which
didn't. With two replicas and only one frozen, the healthy one ACKs almost
immediately and the primary moves on. `Rpl_semi_sync_source_status=ON`
here only tells you "semi-sync is functioning, at least one replica is
keeping up" — it says nothing about `lab10-replica2` specifically, which
could be arbitrarily far behind (or, as in this challenge, completely
frozen) with zero visible symptom on the primary.

**Fix:** if the actual requirement is "a SPECIFIC replica (e.g. the one in
the designated failover DR region) must have every write," semi-sync's
default any-one-of-N behavior doesn't provide that guarantee by itself —
you'd need `rpl_semi_sync_source_wait_no_slave=OFF` (wait for ALL attached
semi-sync replicas) if the durability bar is "every replica has it," or
architectural separation (a dedicated semi-sync pair for the guarantee you
actually need, with other replicas kept fully async and understood as
best-effort) if waiting on all replicas' worst-case latency isn't
acceptable for write throughput.

**Lesson:** "semi-sync is ON" answers "is at least one replica keeping up
with commits," not "is a copy of every committed write everywhere I need
it to be." The moment a topology grows past one replica, that distinction
stops being academic — verify which specific replica(s) you actually need
durability from, and configure (or architect) for that, rather than
assuming the aggregate status variable covers a replica you care about.
