# Lab 29 — Solutions

## Challenge A — the ACL fix wasn't retroactive

**Check:**
```bash
getfacl /srv/shared/alice_file.txt
getfacl /srv/shared
```
The directory has `group:teamB:rwx` in its ACL. `alice_file.txt` does
not — its `getfacl` output shows only the plain owner/group/other bits,
no `teamB` entry at all.

**Diagnosis:** `setfacl -m ... /srv/shared` (without `-R`) modifies exactly
one object: the directory itself. It does not walk existing children. The
directory's ACL only controls operations ON the directory (creating new
entries, listing, etc.) — it has no bearing on permissions of files that
already exist inside it. Those files carry their own, independent ACL
(or lack of one), fixed at whatever it was when they were created. This
is different from the *default* ACL, which only affects objects created
AFTER it's set — neither mechanism reaches back in time to fix existing
content.

**Fix:**
```bash
sudo setfacl -R -m g:teamB:rwx /srv/shared
```
`-R` recurses into every existing file and subdirectory and applies the
same ACL entry to each of them.

**Lesson:** an ACL change on a directory is not retroactive and not
automatically recursive. When you fix access on a directory that already
has content in it, always ask: do I need `-R` for what's already there,
and `-d` for what gets created next? They're two separate concerns and
neither implies the other.

---

## Challenge B — grant one user, one file, without touching group membership

**Check:**
```bash
ls -l /etc/app-secrets.conf
id auditor
sudo -u auditor cat /etc/app-secrets.conf
```
`auditor`'s groups don't include `appteam`, so the file's `640`
(`rw-r-----`) permissions put them squarely in "other" — no access.
Adding `auditor` to `appteam` would fix the read, but `appteam`'s group
bits are `rw-`, so it would also hand `auditor` write access to a
production secrets file — way more than a compliance read-only check
needs.

**Diagnosis:** standard permissions have no concept of "grant read-only to
this one specific extra user." Group membership is all-or-nothing for
whatever that group already grants, and you can't have a second group
bound to a file. This is the single-extra-user variant of the same gap as
the main lab's shared directory — just narrower in scope.

**Fix:**
```bash
sudo setfacl -m u:auditor:r-- /etc/app-secrets.conf
getfacl /etc/app-secrets.conf
```
This grants exactly `r--` to the user `auditor`, and nothing else changes
— `appteam`'s group permissions, the owner's permissions, and `other`'s
lack of access are all untouched. Confirm a third, unrelated user still
gets denied:
```bash
sudo -u rando cat /etc/app-secrets.conf   # still: Permission denied
```

**Lesson:** ACLs aren't just for groups — a per-user ACL entry
(`u:<user>:<perms>`) is the correct tool whenever the ask is "this one
person, this one permission level, this one object," and reaching for
group membership instead almost always grants more than was asked for.
