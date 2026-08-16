# Lab 13 — NFS Stale Mount

## Objective
Produce a genuine "Stale file handle" error on purpose, understand
exactly what makes an NFS filehandle go stale, and recover a client
mount that's stuck pointing at one.

## Why this matters
"Stale file handle" is one of the most confusing NFS errors to hit
cold — the mount looks fine (`mountpoint` says yes, `df` shows it),
the server is often perfectly reachable, and yet every read or write
fails. The confusion comes from what an NFS filehandle actually is: an
opaque reference the client cached, pointing at a specific filesystem
object on the server, generated the first time the client looked it up.
If whatever that filehandle refers to changes underneath it in certain
ways, the reference the client is holding becomes permanently invalid —
no timeout, no retry, no amount of waiting fixes it, because the thing
it pointed at doesn't correspond to anything valid anymore.

## Prerequisites
- A Linux VM, `sudo` access
- This lab runs both the NFS server and client on the same VM
  (loopback NFS) — no second host needed, same technique used in
  `linux/09-process-stuck-in-d-state`

Check first:
```bash
which exportfs mount.nfs showmount
```

## Step 1 — Build the healthy export
```bash
chmod +x setup.sh
./setup.sh
```
This creates a 200M loop-device-backed ext4 filesystem, exports it over
NFS to `127.0.0.1`, mounts it at `/mnt/nfslab13`, and starts a `tail -f`
against a file inside it (simulating an app that keeps a file open
across the mount, the way a log shipper or a long-running read would).

## Step 2 — Confirm it's healthy
```bash
cat /mnt/nfslab13/data.txt
showmount -e 127.0.0.1
```

## Step 3 — Produce a real stale filehandle
```bash
STATE_DIR=/var/lib/nfslab13
EXPORT=/srv/nfslab13

sudo umount "$EXPORT"
sudo losetup -d "$(cat "$STATE_DIR/loopdev")"

sudo dd if=/dev/zero of="$STATE_DIR/disk2.img" bs=1M count=200 status=none
LOOPDEV2=$(sudo losetup --find --show "$STATE_DIR/disk2.img")
sudo mkfs.ext4 -q "$LOOPDEV2"
sudo mount "$LOOPDEV2" "$EXPORT"
echo "hello from a BRAND NEW filesystem, same export path" | sudo tee "$EXPORT/data.txt" > /dev/null
```
Same export path, same NFS export line — but the filesystem backing it
is now a completely different one (different `fsid`, different inode
numbers). Every filehandle the client had cached for the old filesystem
is now meaningless.

## Step 4 — Observe the failure
```bash
cat /mnt/nfslab13/data.txt
```
```
cat: /mnt/nfslab13/data.txt: Stale file handle
```
Not "permission denied," not "no such file" — `ESTALE` specifically.
`ls /mnt/nfslab13` may still show the old listing for a moment
(directory entries can be cached separately) even while reading the
file inside it already fails.

## Step 5 — Try the naive fix (and see why it's not enough)
```bash
sudo umount /mnt/nfslab13
```
This can hang, or fail with `device is busy` — the `tail -f` process
from `setup.sh` still has the old (now-stale) filehandle open, and a
plain `umount` waits for every reference to close first.

## Step 6 — Recover properly
```bash
sudo pkill -f "tail -f /mnt/nfslab13"
sudo umount -f /mnt/nfslab13
sudo mount -t nfs 127.0.0.1:/srv/nfslab13 /mnt/nfslab13
cat /mnt/nfslab13/data.txt
```
`umount -f` forces the unmount even with the stale reference still
technically open; the fresh `mount` re-establishes the connection and
gets brand-new, valid filehandles for the new filesystem.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — `soft` vs `hard`, and what each one actually costs you:**
```bash
./reset.sh
sudo iptables -A OUTPUT -p tcp --dport 2049 -j DROP
sudo iptables -A OUTPUT -p udp --dport 2049 -j DROP
timeout 15 cat /mnt/nfslab13/data.txt; echo "exit code: $?"
```
The default mount (`hard`, no explicit `soft`) doesn't fail — it hangs,
uninterruptibly, until the network path comes back or you give up
waiting. Now compare:
```bash
sudo iptables -D OUTPUT -p tcp --dport 2049 -j DROP
sudo iptables -D OUTPUT -p udp --dport 2049 -j DROP
sudo umount -f /mnt/nfslab13
sudo mount -t nfs -o soft,timeo=30,retrans=2 127.0.0.1:/srv/nfslab13 /mnt/nfslab13
sudo iptables -A OUTPUT -p tcp --dport 2049 -j DROP
sudo iptables -A OUTPUT -p udp --dport 2049 -j DROP
timeout 15 cat /mnt/nfslab13/data.txt; echo "exit code: $?"
sudo iptables -D OUTPUT -p tcp --dport 2049 -j DROP
sudo iptables -D OUTPUT -p udp --dport 2049 -j DROP
```
This one returns an I/O error instead of hanging. Figure out exactly
what `soft` trades away to get that — specifically for *writes*, not
reads — before deciding it's obviously the better default.

**Challenge B — when `umount -f` isn't enough either:**
```bash
./reset.sh
sudo iptables -A OUTPUT -p tcp --dport 2049 -j DROP
sudo iptables -A OUTPUT -p udp --dport 2049 -j DROP
sudo bash -c 'cat /mnt/nfslab13/data.txt &'
sleep 2
sudo umount -f /mnt/nfslab13; echo "exit code: $?"
```
With the server genuinely unreachable (not just stale — actually
unreachable, on a hard mount) and a read already blocked inside the
kernel, plain `umount -f` can itself hang or fail. Find the option that
actually gets you your shell back immediately, understand exactly what
it does differently (does it wait for anything, or not?), and what
state it leaves behind until the underlying access finally resolves one
way or another. Clean up the iptables rules once you're done.

See `solution.md` only after you've formed your own diagnosis.
