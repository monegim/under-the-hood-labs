# Lab 17 — Concept: Why POSIX Permissions Have a Hard Ceiling, and How ACLs Actually Extend Them

## What's actually going on

Every Unix file's permission model boils down to three fixed fields
stored directly in the inode: one owning user, one owning group, and a
9-bit (owner/group/other × read/write/execute) permission mask. This
model has exactly one owning user and exactly one owning group per
object, full stop — there is no field anywhere in a plain inode for "and
also this second, unrelated group." That's not a missing feature so much
as the model's actual shape: it was designed for a simpler access
pattern than "two unrelated teams both need distinct access to the same
shared object," and every workaround that stays within owner/group/other
necessarily distorts something else to compensate — widen the mode bits
(now literally everyone gets that access, not just the two groups that
need it), merge or cross-add group membership (now every member of one
group inherits whatever *else* that group grants access to, elsewhere on
the system, which is scope creep far beyond the one directory you meant
to fix), or reassign the owning group (now you've broken access for
whoever used to have it). None of these are bugs in `chmod`/`chown` —
they're the necessary consequence of a permission model with only one
slot each for "group" and "other."

POSIX ACLs solve this by attaching an *additional*, ordered list of
extra permission entries to an object, stored as an extended attribute on
the filesystem (`system.posix_acl_access` / `system.posix_acl_default`),
without touching the base owner/group/other bits at all.
`setfacl -m g:teamB:rwx /srv/shared` adds exactly one more rule — "group
teamB additionally gets rwx here" — layered on top of, not instead of, the
existing mode. `getfacl` on a file with no ACL entries yet just echoes the
plain mode bits back, because there's genuinely nothing else to report;
once you add an entry, the kernel's access-check logic gains an extra step
beyond the traditional owner/group/other comparison. A subtlety that trips
people up (and is exactly what Step 4's gotcha shows): every ACL-bearing
object also carries a **mask** entry, which caps the *effective*
permission of every named-user/named-group ACL entry to whatever the mask
allows — so an entry can say `rwx` while `getfacl`'s `#effective:` comment
shows something narrower, because the file's base group permission bits
(set at creation time via the umask) constrain what the mask permits. This
is why checking the `#effective:` line, not just the raw ACL entry, is the
only way to know what access a rule actually grants.

Two properties of ACLs matter enormously in practice and are exactly what
the two challenges test. First, an ACL set on a directory is **not
retroactive** — `setfacl -m ... /srv/shared` (no `-R`) touches only the
directory object itself; every file that already existed inside it keeps
whatever ACL (or lack of one) it had at creation time, completely
unaffected, because the directory's ACL only governs operations *on the
directory* (creating entries, listing), not the independent permission
state of its existing children. Fixing existing content requires `-R`
(recursive) explicitly. Second, and separately, a **default ACL**
(`setfacl -d`) only affects objects created *after* it's set — it's
inherited at creation time by new children, but it doesn't reach
backward either. `-R` and `-d` solve two different time directions (past
vs future) and neither implies the other; a real fix to a directory that
already has content and will keep growing typically needs both. Finally,
ACL entries aren't limited to groups — a per-user entry
(`u:auditor:r--`) grants exactly one specific permission level to exactly
one specific person on exactly one object, which is the correct tool
whenever the actual ask is narrower than "this whole group" (Challenge
B's compliance-auditor scenario), and reaching for group membership
instead almost always grants strictly more access than was asked for.

## Where this shows up in the real world

Shared upload directories, deploy artifact paths, and any config or
secrets file that a second team (or an auditor, on a one-off compliance
basis) needs read access to without joining the owning team's group are
all real, recurring instances of this exact gap. The naive fixes —
`chmod 777`, merging groups, adding a user to a group they don't actually
belong in organizationally — are common precisely because they're the
first thing that occurs to someone under time pressure, and they're all
security regressions relative to what was actually asked for. Knowing
that ACLs exist specifically to grant one extra user or group exactly the
access they need, on exactly the object that needs it, without touching
anything else, is what separates a scoped, auditable fix from an
access-control incident waiting to be discovered later.

## Go deeper

- **Book:** *The Linux Programming Interface* — Michael Kerrisk — has a dedicated, thorough chapter on POSIX ACLs, their storage as extended attributes, and the mask entry's role.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man5/acl.5.html — the canonical reference for ACL semantics, including default ACLs and the mask, plus `setfacl(1)`/`getfacl(1)` for exact flag behavior.
- **Website/docs:** Arch Linux Wiki — https://wiki.archlinux.org — has a clear, practical ACL page covering recursive application and default-ACL inheritance.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — covers Linux permissions and ACLs in practical, hands-on administration content.
