# Lab 19 — Solutions

## Challenge A — valid files, wrong root UUID

**Check:**
```bash
cat /boot/grub/grub.cfg | grep -A 6 "Challenge A"
blkid
findmnt -no UUID /
```
The entry's `root=UUID=00000000-0000-0000-0000-000000000000` matches
nothing `blkid` reports on this system. `findmnt -no UUID /` shows the
real UUID of your actual root filesystem, which looks nothing like the
placeholder in the decoy entry.

**Diagnosis:** unlike the main lab, GRUB itself has no problem here - the
kernel and initrd files it's told to load both genuinely exist, so it
loads them and hands off control successfully. The failure happens one
stage later, inside the kernel/initramfs: early userspace tries to find a
block device with that UUID to mount as root, finds nothing, and (once it
gives up waiting) panics with something like
`VFS: Unable to mount root fs on unknown-block(0,0)`, or the initramfs's
own boot scripts print `Gave up waiting for root device` and drop to an
`(initramfs)` busybox shell instead. This is exactly the kind of stale
config that results from hand-editing a GRUB entry, or from a disk
clone/re-image that changed the filesystem's UUID without anyone updating
the entry that references the old one - `update-grub`/`grub-mkconfig`
would normally regenerate this correctly from the live system, which is
exactly why hand-edited entries that bypass it are the risky path.

**Fix:**
```bash
REAL_UUID="$(findmnt -no UUID /)"
sudo sed -i "s/root=UUID=00000000-0000-0000-0000-000000000000/root=UUID=$REAL_UUID/" /etc/grub.d/47_lab19_challenge_a
sudo update-grub
cat /boot/grub/grub.cfg | grep -A 6 "Challenge A"
```

**Lesson:** GRUB successfully loading a kernel and initrd tells you
nothing about whether that kernel will actually be able to mount its root
filesystem - those are two entirely separate stages of the boot chain,
with two entirely different failure signatures (`grub rescue>` / "file
not found" versus a kernel panic or an `(initramfs)` shell). Always
regenerate boot configuration from the live system's real state
(`update-grub`) rather than hand-editing UUIDs, device paths, or kernel
filenames directly.

---

## Challenge B — persistent default vs one-time next boot

**Check:**
```bash
sudo grub-editenv list
grep GRUB_DEFAULT /etc/default/grub
```
`saved_entry=` in `grub-editenv list` now names the broken decoy entry.
`/etc/default/grub`'s `GRUB_DEFAULT` line is untouched - still `0` (or
whatever it was).

**Diagnosis:** `grub-set-default` and `grub-reboot` both work by writing
to the same small environment block (`grubenv`, usually
`/boot/grub/grubenv`), read by GRUB at boot time to decide which entry to
select when `GRUB_DEFAULT=saved` (Ubuntu's default). The difference is
durability: `grub-set-default` writes a value that stays until explicitly
changed again - every future boot uses it. `grub-reboot` writes a value
that GRUB itself clears the next time it boots, regardless of whether
that boot succeeded - so it's a true one-shot. Using `grub-set-default`
on an entry you haven't fully verified yet (as this challenge did, on
purpose) means a mistake here doesn't just risk the next reboot - it risks
*every* reboot until someone notices, which in practice tends to be
whenever the box next restarts for an unrelated reason (a patch cycle, a
power event, a host migration) - the worst possible moment to discover it,
for the same underlying reason Lab 12 calls out.

**Fix:**
```bash
sudo grub-set-default 0
sudo grub-editenv list
```

**Lesson:** when testing an unverified boot entry, `grub-reboot` is almost
always the right tool - it bounds the blast radius to exactly one boot,
automatically, even if you forget to undo anything. `grub-set-default`
should only be used once you're confident the entry actually works.

---

## Main incident recap (for reference)

**Check:**
```bash
ls -la /boot/*lab19*
file /boot/initrd.img-lab19-test
```

**Diagnosis:** the decoy entry's kernel file existed but its initrd did
not - the exact symptom of an interrupted or partially-completed kernel
install (classic cause: the disk filled up mid-`apt upgrade`, or someone
copied a kernel image manually without also generating its initramfs).
Because this failure happens at the GRUB stage (GRUB itself can't locate
the file it was told to load), it's the earliest and cleanest of this
lab's three failure modes to diagnose statically - the file is either
there or it isn't.

**Fix:**
```bash
sudo update-initramfs -c -k "$(uname -r)" -o /boot/initrd.img-lab19-test
```

**Lesson:** `update-initramfs -o` lets you regenerate a valid initramfs to
an arbitrary output path for any kernel version that's actually installed
(has a `/lib/modules/<version>` directory) - useful both for fixing a
missing/corrupt initrd in place and, as in this lab, for safely
reproducing one without touching your real per-kernel file.
