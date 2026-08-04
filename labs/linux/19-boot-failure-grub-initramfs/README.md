# Lab 19 — Boot Failure: GRUB and initramfs

## Objective
Diagnose boot-chain failures that happen *before* systemd/journald even
start - a kernel whose initramfs never got generated, a boot entry with a
stale root device UUID, and a persistent default pointed at a broken
entry - by reading `grub.cfg` and initramfs internals directly, the same
way you would from a rescue environment.

## Why this matters
Lab 12 covers a service that fails after boot, where you still have SSH,
`journalctl`, and a full running system to diagnose with. GRUB/initramfs
failures are a category earlier and meaner than that: if the *default*
boot entry is broken, the machine can come up with no network, no SSH,
and no systemd units running at all - reachable only via a serial/hypervisor
console, if at all. Recognizing the difference between "GRUB can't find
the kernel/initrd file" (fails at the boot loader stage, before Linux even
starts) and "the kernel booted but can't mount root" (fails inside the
kernel/initramfs, one stage later) tells you where to actually look, and
whether you're looking at a GRUB config problem or a storage/root-device
problem.

## Prerequisites
- Ubuntu VM (BIOS/GRUB2, not a bare UEFI-only appliance), sudo access
- `grub-common`/`grub-pc` or `grub-efi` (already installed on any standard
  Ubuntu install), `lsinitramfs` (part of `initramfs-tools`)

Check first:
```bash
uname -a
which update-grub grub-editenv lsinitramfs
cat /etc/default/grub | grep GRUB_DEFAULT
```

> **Honesty about what's simulated here, matching Lab 12's approach:**
> Lab 12's bug surfaces *after* boot, so a real `sudo reboot` to verify it
> is genuinely safe - SSH comes back either way. A broken GRUB entry can
> mean SSH never comes back. So this lab does **not** touch your real
> default boot entry or force a reboot. Instead, `setup.sh` adds an
> **extra, non-default** GRUB menu entry - a decoy - built from real
> copies of your actual kernel/initrd, and then genuinely corrupts *that*
> (not your real one). Everything you diagnose is 100% real GRUB/
> initramfs content, read the same way you'd read it after booting a
> rescue ISO - it's just that we guarantee your own bootable path is never
> at risk. If you have real console access (serial console, IPMI/iLO, a
> hypervisor console, or a local VirtualBox/VMware/KVM window - not just
> SSH) and want to see the literal failure at boot, Challenge B shows you
> the one command that would make it your actual next boot, and how to
> undo it immediately after.

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This copies your real kernel/initrd to decoy filenames, adds a custom GRUB
menu entry pointing at them, runs `update-grub`, and then deletes the
decoy initrd - simulating a kernel upgrade where the new kernel image
landed but initramfs generation/copy never completed (disk full mid-
upgrade is the classic real-world cause).

## Step 2 — Confirm your real boot path is untouched
```bash
sudo grub-editenv list
grep GRUB_DEFAULT /etc/default/grub
```
No `saved_entry` pointing anywhere near "lab19", and `GRUB_DEFAULT` is
whatever it was before (usually `0`, the first/real entry). This is the
whole safety model of this lab - confirm it before going further.

## Step 3 — Read the broken entry
```bash
cat /boot/grub/grub.cfg | grep -A 6 "Lab 19 - test kernel"
```
Note the exact `linux`/`initrd` lines and which files they reference, then
check those files:
```bash
ls -la /boot/*lab19*
```
The kernel (`vmlinuz-lab19-test`) is there. The initrd
(`initrd.img-lab19-test`) is **not**.

## Step 4 — Understand what this would actually do at boot
If this entry were ever selected, GRUB has to locate and load both files
named on the `linux`/`initrd` lines *before* it hands control to the
kernel at all. A missing initrd file at this stage is a boot-loader-level
failure - GRUB reports something like `error: file '/initrd.img-lab19-test'
not found`, and either falls back to the next menu entry, or if this were
somehow the *only* entry, it would drop you to a `grub rescue>` prompt
where the kernel has never even started. This is a different, earlier
failure than the "kernel booted but couldn't mount root" class from
Challenge A.

## Step 5 — Fix it
The real fix for "initramfs is missing/corrupt for a kernel that's
actually installed" is regenerating it - `update-initramfs -c` builds one
for an installed kernel version, and `-o` lets you target our decoy
filename instead of the real per-kernel path:
```bash
sudo update-initramfs -c -k "$(uname -r)" -o /boot/initrd.img-lab19-test
ls -la /boot/initrd.img-lab19-test
file /boot/initrd.img-lab19-test
```
Compare it to your real initrd to confirm it's a legitimate archive:
```bash
file /boot/initrd.img-$(uname -r)
```
Both should report the same kind of archive (cpio/gzip).

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — kernel and initrd both load fine, but root still won't
mount:**
```bash
sudo cp /boot/vmlinuz-lab19-test /boot/vmlinuz-lab19-challenge-a
sudo update-initramfs -c -k "$(uname -r)" -o /boot/initrd.img-lab19-challenge-a
sudo tee /etc/grub.d/47_lab19_challenge_a > /dev/null <<'EOF'
#!/bin/sh
exec tail -n +3 $0
menuentry "Lab 19 Challenge A - test kernel (DO NOT SELECT - decoy, do not boot this)" {
	echo "Loading Lab 19 Challenge A kernel..."
	linux /boot/vmlinuz-lab19-challenge-a root=UUID=00000000-0000-0000-0000-000000000000 ro
	echo "Loading Lab 19 Challenge A initrd..."
	initrd /boot/initrd.img-lab19-challenge-a
}
EOF
sudo chmod +x /etc/grub.d/47_lab19_challenge_a
sudo update-grub
```
This time both files genuinely exist and are valid. Compare the `root=`
value in this entry against your real root device:
```bash
cat /boot/grub/grub.cfg | grep -A 6 "Challenge A"
blkid
findmnt /
```
Diagnose why this entry, unlike the main lab's, would get all the way
through GRUB and into the kernel before failing - and what the kernel's
actual panic message tends to look like when this happens
(`VFS: Unable to mount root fs on unknown-block(0,0)` is the classic one).
Fix the entry so its `root=` matches your real filesystem's UUID.

**Challenge B — the persistent default, not just a one-off boot:**
```bash
sudo grub-set-default "Lab 19 - test kernel (DO NOT SELECT - decoy, do not boot this)"
sudo grub-editenv list
grep GRUB_DEFAULT /etc/default/grub
```
`grub-editenv list` now shows `saved_entry=` pointing at the decoy - this
is a **persistent** change (survives every future reboot, not just the
next one), and notice `/etc/default/grub`'s `GRUB_DEFAULT` line is
unchanged - `grub-set-default` writes to a separate file (`grubenv`), not
`/etc/default/grub`. Diagnose the difference between this and
`grub-reboot` (which sets a **one-time-only** next-boot entry that reverts
automatically), and why `grub-set-default` pointed at something broken is
the more dangerous mistake of the two - it doesn't just risk the next
reboot, it risks every reboot until someone notices. If you have real
console access and want to see the literal failure, this is the safe way
to do it: `grub-reboot` (not `grub-set-default`) the decoy entry, reboot,
watch it fail at the console, then power-cycle again - `grub-reboot`'s
one-time entry is already consumed, so the second reboot returns to your
real default automatically even without fixing anything.

Fix the persistent default back:
```bash
sudo grub-set-default 0
sudo grub-editenv list
```

See `solution.md` only after you've formed your own diagnosis.
