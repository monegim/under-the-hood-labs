# Lab 17 — Permissions vs ACLs

## Objective
Build a real incident that standard Unix permissions (owner/group/other)
genuinely cannot solve cleanly, then fix it properly with POSIX ACLs
(`getfacl`/`setfacl`).

## Why this matters
Classic `chmod`/`chown` gives you exactly ONE owning user and ONE owning
group per file. That's fine until a shared resource needs access from two
unrelated groups at once — a very common real scenario (a shared uploads
directory, a deploy artifact path, a config file an auditor needs to read
without joining the app team). The naive "fixes" people reach for are all
bad:
- `chmod 777` (or `770` opened wider) — now literally everyone can write,
  not just the two groups that need it.
- Merge the two groups into one, or add users to each other's groups —
  now every member of teamB also inherits whatever ELSE teamA's group
  membership grants access to, somewhere else on the system. You've
  widened access far beyond the one directory you meant to fix.
- Change the file's owning group — you just broke access for whichever
  group used to own it.

ACLs exist for exactly this gap: attach permissions for an *additional*,
specific user or group to an object, without touching the base
owner/group/other bits at all.

## Prerequisites
- Linux VM, `sudo` access
- `acl` package (`getfacl`, `setfacl`) — installed by `setup.sh` if missing

Check first:
```bash
which getfacl setfacl
```

## Step 1 — Build the incident
```bash
chmod +x setup.sh
./setup.sh
```
This creates two unrelated groups (`teamA`, `teamB`) and two users
(`alice` in `teamA`, `bob` in `teamB`), then a shared directory
`/srv/shared` owned `root:teamA` mode `770`. `alice` can write to it.
`bob` cannot — confirmed by the script.

## Step 2 — Confirm the standard-permissions dead end
```bash
ls -ld /srv/shared
getfacl /srv/shared
```
`getfacl` on a file with no ACLs yet just echoes the standard
owner/group/other bits — that's your confirmation there's nothing beyond
plain Unix permissions here.

Try the "obvious" bad fixes and reason about why each is wrong instead of
actually running them:
- `chmod 777 /srv/shared` — solves it for bob, breaks it for everyone else
  on the box.
- `usermod -aG teamA bob` — bob now has teamA's access everywhere teamA
  has access, not just this one directory.

## Step 3 — Fix it properly with an ACL
```bash
sudo setfacl -m g:teamB:rwx /srv/shared
getfacl /srv/shared
```
Now `bob` can write:
```bash
sudo -u bob touch /srv/shared/bob_file.txt
ls -l /srv/shared
```
> Gotcha: an ACL entry only applies to the object you set it on. A NEW
> directory or file created inside `/srv/shared` afterward does **not**
> automatically get `teamB`'s ACL unless you also set a **default** ACL
> on the directory:
> ```bash
> sudo setfacl -d -m g:teamB:rwx /srv/shared
> ```
> Without the `-d` (default) entry, every future file created in
> `/srv/shared` reverts to just owner/group/other again, and bob loses
> access to anything created after your fix.

## Step 4 — Verify inheritance works
```bash
sudo -u alice mkdir /srv/shared/subdir
getfacl /srv/shared/subdir
sudo -u alice touch /srv/shared/newfile.txt
getfacl /srv/shared/newfile.txt
sudo -u bob sh -c 'echo hi >> /srv/shared/newfile.txt' && echo "bob can write the new file too"
```
> Gotcha: notice `getfacl` on the new plain file shows entries like
> `group:teamB:rwx  #effective:rw-`. New files are created with a base
> mode (usually `664`/`644` before the umask) that has no execute bit —
> the ACL **mask** caps the effective permission down to what the mode
> allows, even though the ACL entry itself says `rwx`. This trips people
> up: the ACL entry can say `rwx` while the `#effective:` comment shows
> something more restrictive — always check the effective column, not
> just the raw entry.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A:**
```bash
sudo -u bob sh -c 'echo update >> /srv/shared/alice_file.txt'
```
`bob` can write brand-new files in `/srv/shared` fine (Step 3/4 fixed
that), but this fails on `alice_file.txt` — the file `setup.sh` created
BEFORE you ran `setfacl`. Diagnose why this one file behaves differently
from everything created afterward, and what command fixes it (hint: think
about scope — a single `setfacl` invocation without a particular flag only
touches the object you name).

**Challenge B:**
```bash
sudo groupadd -f appteam
sudo useradd -m auditor 2>/dev/null || true
sudo bash -c 'echo "db_password=hunter2" > /etc/app-secrets.conf'
sudo chown root:appteam /etc/app-secrets.conf
sudo chmod 640 /etc/app-secrets.conf
sudo -u auditor cat /etc/app-secrets.conf
```
Note `auditor` is deliberately NOT added to `appteam` here — that's the
point. `auditor` needs read-only access to this one file for a compliance
check, nothing else, and specifically without joining `appteam` (which
would also hand them access to anything else `appteam` owns elsewhere).
Diagnose the cleanest fix, and make sure a random third user still can't
read the file afterward.

See `SOLUTION.md` only after you've formed your own diagnosis.
