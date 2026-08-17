# Lab 20 — Solutions

## Challenge A — "I saved it" can be half true

**Check:**
```bash
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT * FROM mysql_servers;"
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "SELECT * FROM mysql_users;"
```
After the restart, `mysql_servers` comes back with the `primary` row
fully intact. `mysql_users` comes back completely empty.

**Diagnosis:** the setup ran `SAVE MYSQL SERVERS TO DISK` but never ran
`SAVE MYSQL USERS TO DISK`. ProxySQL's configuration isn't one blob you
persist or don't — it's split into independent categories (servers,
users, query rules, and more), each with its own `LOAD ... TO RUNTIME`
and `SAVE ... TO DISK` pair. Saving one category has no effect on any
other. "I ran SAVE TO DISK" is a claim about exactly one slice of the
configuration, not a statement about the whole thing — and it's easy to
genuinely believe you saved everything after only saving the one part
you were actively thinking about when the incident that prompted the
change was about routing (servers), not credentials (users).

**Fix:** save every category you touched, every time —
`SAVE MYSQL SERVERS TO DISK; SAVE MYSQL USERS TO DISK;` together, as a
single habit rather than two separate ones you might remember
independently. If you're not sure what you've touched, `SAVE MYSQL
SERVERS TO DISK; SAVE MYSQL USERS TO DISK; SAVE MYSQL QUERY RULES TO
DISK; SAVE MYSQL VARIABLES TO DISK;` — running all of them costs
nothing when a category has no pending changes.

**Lesson:** partial persistence is more dangerous than no persistence,
because it looks like success. A `SAVE` that ran without error, on a
category you can point to and confirm survived a restart, builds
exactly the kind of confidence that stops you from checking the
categories you didn't happen to think about.

---

## Challenge B — the "reload config" command that goes the wrong way

**Check:**
```bash
docker exec lab20-proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
  LOAD MYSQL USERS FROM DISK;
  LOAD MYSQL USERS TO RUNTIME;
"
docker exec lab20-proxysql mysql -h127.0.0.1 -P6033 -uurgentuser -purgentpass appdb -e "SELECT 1;"
```
`urgentuser` — added live, working, and never saved — is gone.
`appuser`, saved before any of this happened, is unaffected.

**Diagnosis:** ProxySQL's configuration commands come in two families
that move data in opposite directions, and they're easy to confuse
because both have "MYSQL USERS" and a location in their name:

- `LOAD MYSQL USERS TO RUNTIME` — moves data from the working
  `mysql_users` table into the active `RUNTIME` config. This is the
  familiar, safe-feeling one used constantly throughout this lab.
- `SAVE MYSQL USERS TO DISK` — moves data from the working table to
  the on-disk config. Also familiar by now.
- `LOAD MYSQL USERS FROM DISK` — moves data the *other* way: from the
  on-disk config *back into* the working `mysql_users` table,
  overwriting whatever was there. Anything in the working table that
  hadn't been saved yet — `urgentuser`, in this case — is simply
  replaced by whatever the last save actually contained, which didn't
  include it.

Someone running `LOAD ... FROM DISK` while believing it "reloads" or
"re-syncs" ProxySQL's config is reasoning from the command's English
name, not its actual direction — and the name genuinely supports that
reading. There's nothing reckless-looking about it; it's the kind of
command a careful person runs specifically to double-check things are
consistent, which makes it worse when it turns out to be the one that
just deleted someone's unsaved work.

**Fix:** there isn't a way to undo this once run — `urgentuser`'s
configuration has to be re-entered and, this time, actually saved.
Going forward: before running any `... FROM DISK` command, check
whether the working tables currently hold anything that hasn't been
`SAVE`d yet (Step 3's working-table-vs-`disk`-database comparison is
exactly this check) — if they do, `FROM DISK` is about to discard it.

**Lesson:** `TO`/`FROM` in these command names describes data flow
direction, not "make things current" versus "make things stale" — and
guessing at the direction from what sounds intuitive is exactly how you
end up running the one command in this whole family that deletes
unsaved work instead of protecting it.
