# Lab 3 — Classic Deadlock: Opposite Lock Order

## Objective
Reproduce a textbook InnoDB deadlock (two transactions updating the same
two rows in opposite order), read the actual deadlock graph in `SHOW
ENGINE INNODB STATUS`, and understand why the application-level fix
(retry the loser) and the schema/code-level fix (consistent lock order)
are both "correct" — they solve different halves of the problem.

## Why this matters
Deadlocks are not bugs in MySQL — they are an expected, designed-for
outcome of concurrent transactions taking locks in different orders.
InnoDB detects the circular wait and kills one transaction to break the
cycle; that transaction's writes are rolled back and it receives error
1213. If the application doesn't catch that specific error and retry the
transaction, the write is just silently lost from the app's point of
view (or worse, surfaced as a 500 to a user who then has no idea whether
their action succeeded). The single most common on-call confusion: staring
at row-level locking config trying to "fix" the deadlock, when a deadlock
under concurrent writes is not itself the incident — an application that
doesn't retry on 1213 is.

## Prerequisites
- Ubuntu VM, sudo access
- `mysql-server` (installed by `setup.sh`)

Check first:
```bash
uname -a
which mysql
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This creates an `accounts` table (`id=1` and `id=2`, both starting at
balance 1000) and fires two concurrent "transfers" in opposite row lock
order:
- **Transfer A:** locks `id=1`, sleeps 2s, then locks `id=2` (moves 100
  from account 1 to account 2)
- **Transfer B:** locks `id=2`, sleeps 2s, then locks `id=1` (moves 50
  from account 2 to account 1)

Both sleep just long enough that by the time each tries to grab its
*second* lock, the other transaction already holds it — a guaranteed
circular wait.

## Step 2 — See which transaction lost
```bash
cat /tmp/lab03-transfer-a.log /tmp/lab03-transfer-b.log
```
One of the two logs shows:
```
ERROR 1213 (40001) at line 3: Deadlock found when trying to get lock; try restarting transaction
```

## Step 3 — Read the actual deadlock graph
```bash
mysql -uroot -prootpass -e "SHOW ENGINE INNODB STATUS\G" | sed -n '/LATEST DETECTED DEADLOCK/,/^---TRANSACTION/p'
```
> Gotcha: this section is only populated with the **most recent** deadlock
> — if you run other transactions afterward, it can be overwritten before
> you look. Capture it right away.

Look for two `*** (1) TRANSACTION:` / `*** (2) TRANSACTION:` blocks, each
followed by `*** WAITING FOR THIS LOCK TO BE GRANTED:` — this is the
literal lock-order conflict: transaction 1 holds the lock transaction 2
wants, and vice versa. The line `*** WE ROLL BACK TRANSACTION (N)` at the
end tells you which one InnoDB picked as the victim (usually the one that
had done less work / would be cheaper to roll back).

## Step 4 — Confirm the actual data state
```bash
mysql -uroot -prootpass appdb -e "SELECT * FROM accounts;"
```
Only ONE of the two transfers is reflected. Total balance is still
consistent (money wasn't created or destroyed — the rolled-back
transaction's partial UPDATE was fully undone), but the specific transfer
that lost is simply missing.

## Step 5 — Fix it: retry the loser
Figure out from Step 2/3 which transfer (A or B) got rolled back, then
manually re-run **only that one**:
```bash
# example if transfer B was the victim:
mysql -uroot -prootpass appdb -e "
  BEGIN;
  UPDATE accounts SET balance = balance - 50 WHERE id = 2;
  UPDATE accounts SET balance = balance + 50 WHERE id = 1;
  COMMIT;
"
mysql -uroot -prootpass appdb -e "SELECT * FROM accounts;"
```
Both transfers are now reflected: `id=1` at 950, `id=2` at 1050.

> The real fix isn't "run this SQL" — it's that the application code
> issuing these transfers needs a retry loop around error 1213
> specifically (most MySQL drivers expose this as a distinct exception
> type, e.g. `Deadlock found`/`SQLSTATE 40001`), so this reconciliation
> happens automatically instead of silently dropping a transfer.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a deadlock from INSERTs, not UPDATEs:**
```bash
mysql -uroot -prootpass appdb -e "
  DROP TABLE IF EXISTS signups;
  CREATE TABLE signups (id INT AUTO_INCREMENT PRIMARY KEY, email VARCHAR(100) UNIQUE);
"
mysql -uroot -prootpass appdb -e "
  BEGIN;
  INSERT INTO signups (email) VALUES ('alice@example.com');
  DO SLEEP(2);
  INSERT INTO signups (email) VALUES ('bob@example.com');
  COMMIT;
" > /tmp/lab03-insert-a.log 2>&1 &
mysql -uroot -prootpass appdb -e "
  BEGIN;
  INSERT INTO signups (email) VALUES ('bob@example.com');
  DO SLEEP(2);
  INSERT INTO signups (email) VALUES ('alice@example.com');
  COMMIT;
" > /tmp/lab03-insert-b.log 2>&1 &
wait
cat /tmp/lab03-insert-a.log /tmp/lab03-insert-b.log
```
No `UPDATE` statement anywhere, yet you'll likely see either a deadlock or
a lock-wait-timeout here too. Read the deadlock/lock section of `SHOW
ENGINE INNODB STATUS` and figure out what kind of lock two plain `INSERT`s
into a `UNIQUE`-keyed column are actually contending on (hint: it isn't a
row that exists yet).

**Challenge B — a three-way deadlock cycle:**
```bash
mysql -uroot -prootpass appdb -e "
  UPDATE accounts SET balance=1000 WHERE id IN (1,2);
  INSERT INTO accounts (id, balance) VALUES (3, 1000) ON DUPLICATE KEY UPDATE balance=1000;
"
mysql -uroot -prootpass appdb -e "BEGIN; UPDATE accounts SET balance=balance-1 WHERE id=1; DO SLEEP(3); UPDATE accounts SET balance=balance+1 WHERE id=2; COMMIT;" > /tmp/lab03-3way-a.log 2>&1 &
mysql -uroot -prootpass appdb -e "BEGIN; UPDATE accounts SET balance=balance-1 WHERE id=2; DO SLEEP(3); UPDATE accounts SET balance=balance+1 WHERE id=3; COMMIT;" > /tmp/lab03-3way-b.log 2>&1 &
mysql -uroot -prootpass appdb -e "BEGIN; UPDATE accounts SET balance=balance-1 WHERE id=3; DO SLEEP(3); UPDATE accounts SET balance=balance+1 WHERE id=1; COMMIT;" > /tmp/lab03-3way-c.log 2>&1 &
wait
cat /tmp/lab03-3way-a.log /tmp/lab03-3way-b.log /tmp/lab03-3way-c.log
mysql -uroot -prootpass -e "SHOW ENGINE INNODB STATUS\G" | sed -n '/LATEST DETECTED DEADLOCK/,/^---TRANSACTION/p'
```
Three sessions, each waiting on the next in a cycle (1→2→3→1). Only ONE of
the three logs will show error 1213 — the other two eventually commit.
Trace the full wait-for cycle in the deadlock output (not just the two
transactions InnoDB names in its victim decision) and explain why exactly
one victim is enough to unblock all three, even though three sessions were
involved.

See `solution.md` only after you've formed your own diagnosis.
