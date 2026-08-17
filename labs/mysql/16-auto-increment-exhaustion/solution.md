# Lab 16 — Solutions

## Challenge A — a quick fix that doubles headroom without changing the storage size

**Check:**
```bash
docker exec lab16-primary mysql -uroot -prootpass appdb -e "SHOW CREATE TABLE orders\G"
```
Exhaustion hit at `id=127` with plain `TINYINT` (signed); after `MODIFY
id TINYINT UNSIGNED AUTO_INCREMENT`, inserts continue past 127, all the
way toward 255.

**Diagnosis:** `TINYINT` is always exactly 1 byte of storage, signed or
unsigned — the *storage size* never changes between the two. What
changes is which 256 integers that byte can represent: `-128` to `127`
signed, or `0` to `255` unsigned. An `AUTO_INCREMENT` column
conventionally starts at 1 and only ever counts upward — it never uses
the negative half of a signed range at all. So for this specific use
case, the negative half of the signed range (`-128` to `-1`, 128 unused
values) was pure waste. Converting to `UNSIGNED` doesn't add storage or
change the type's precision — it just reclaims that wasted lower half
for the counter to use, which is why the usable ceiling roughly doubles
(127 → 255) for zero additional bytes per row.

**Fix (already applied above):**
```bash
docker exec lab16-primary mysql -uroot -prootpass appdb -e "
  ALTER TABLE orders MODIFY id TINYINT UNSIGNED AUTO_INCREMENT;
"
```

**Lesson:** before jumping straight to a wider column type (which does
change every row's storage size, and on a large table means a real
`ALTER TABLE` with real disk, I/O, and potential locking cost — MySQL
8.0 can do this particular change `INPLACE` without a full table rebuild
in many cases, but that's a property of the specific column change, not
a guarantee for every `ALTER TABLE`), check whether the column is even
using the unsigned attribute already. It's a genuinely legitimate,
zero-cost lever — but it only buys roughly 2x, one time, not an escape
from ever needing a real widening `ALTER TABLE` as growth continues.

---

## Challenge B — the counter runs out far faster than the insert count predicts

**Check:**
```bash
docker exec lab16-primary mysql -uroot -prootpass appdb -e "SELECT COUNT(*) FROM orders; SHOW CREATE TABLE orders\G"
```
20 rows inserted, but the counter jumped to roughly 201 — about 10x the
row count, not 1:1.

**Diagnosis:** `auto_increment_increment` controls the step size between
consecutive auto-generated values — the default is 1 (every insert
advances the counter by exactly 1), but it's commonly set higher
specifically for multi-primary/multi-writer replication topologies
(classic MySQL circular replication, Galera Cluster, Group Replication in
multi-primary mode) as a collision-avoidance scheme: each writer node
gets a different `auto_increment_offset` (1, 2, 3, ...) combined with the
same cluster-wide `auto_increment_increment` (e.g. 10, or the node
count), so concurrently-inserting nodes generate ID sequences that
interleave without ever colliding on the same value — no coordination
between nodes required for every single insert. The tradeoff is direct
and unavoidable: an increment of 10 means every single insert, on every
node, burns 10 values of ID space for 1 actual row, so the *effective*
capacity of a given column type is divided by the increment, cluster-wide,
not just per-node.

**Fix:** there's no "undo" here — the fix is accounting for it correctly
in capacity planning:
```bash
docker exec lab16-primary mysql -uroot -prootpass -e "SHOW VARIABLES LIKE 'auto_increment_increment';"
```
Multiply expected row growth by this value (not by 1) when estimating
how long a given column width will last, and size the column
accordingly from the start on any table running in this kind of
topology.

**Lesson:** "rows per day" is not the same number as "IDs consumed per
day" the moment `auto_increment_increment` is anything other than 1 —
which is exactly the kind of cluster-wide setting that's easy to forget
about when a single engineer is doing capacity math against a single
node's insert rate.
