# Lab 12 — Concept: systemd Ordering vs Dependencies, and Why Boot-Time Bugs Are Invisible Day-to-Day

## What's actually going on

systemd starts units in parallel by default, precisely because doing so
makes boot fast — there's no reason to serialize starting an SSH daemon
and a web server if neither depends on the other. But parallel startup
means any two services that *do* have a real dependency need to say so
explicitly, or systemd has no way to know they can't just race. This lab's
core bug — `webapp.service` assuming MySQL is already up, with nothing in
its unit file saying so — is exactly that gap. On a running system that's
never rebooted, `mysql.service` is already active from whenever it was
last started, so the missing dependency declaration is invisible; it only
matters at the one moment both units are being brought up together, which
in practice means "at boot" or "at a full cluster restart" — precisely the
worst, least-tested moment for this class of bug to surface, and why it
can pass every day-to-day check and only bite on the reboot that matters.

systemd actually has two separate concepts here that people conflate, and
distinguishing them is the entire point of Challenge A. **`After=`** (and
its counterpart `Before=`) is a pure *ordering* constraint: if both units
end up in the same transaction, start this one later. It says nothing
about whether the other unit even exists, is enabled, or succeeds —
it only constrains relative timing *if* both are already being started.
**`Requires=`** (or the softer `Wants=`) is what actually pulls the other
unit into the transaction as a real dependency and fails (or, with
`Wants=`, merely proceeds without insisting) if that unit can't start.
This is exactly why Challenge A's fix — adding `After=mysql.service`
without `Requires=` — didn't help once `mysql.service` was masked: with
mysql masked, nothing ever asks systemd to start it in the first place, so
there's no transaction for the ordering constraint to apply to at all;
`webapp` just starts on its own schedule as if `After=` weren't there.
`Requires=` is what would have pulled mysql into the transaction and
failed `webapp` cleanly with an explicit dependency-failure message
instead of starting anyway and failing later at the application level
(the `mysqladmin ping` check in `ExecStartPre` or similar). In practice
you almost always want both together: `Requires=` to guarantee the
dependency is actually being started, `After=` to guarantee it's started
*first*.

Mount units are a related but distinct mechanism, and Challenge B exposes
it. systemd auto-generates a `.mount` unit from every line in
`/etc/fstab` via `systemd-fstab-generator`, run early in the boot
sequence, and by default that generated mount is pulled in as a
requirement of `local-fs.target` — unless the fstab entry carries the
`nofail` option. A typo'd device path in `/etc/fstab` is completely
harmless on a running system (nothing re-reads fstab spontaneously), which
is exactly why it sits silent until the next full boot or an explicit
`mount -a`/`daemon-reload` — at which point the generated mount unit fails,
`local-fs.target` doesn't reach the state services expect, and anything
declaring `RequiresMountsFor=` on that path fails as a downstream
consequence of a config file, not of anything wrong with its own unit
definition. This is structurally the same "only matters at boot" trap as
the MySQL ordering bug, just one layer removed — a dependency chain
(service → mount target → generated mount unit → fstab line) rather than
a direct service-to-service dependency.

## Where this shows up in the real world

"It worked before the reboot, now it's dead" is one of the most common
infrastructure tickets, and the root cause is almost always exactly this
class of bug: two units that happen to start in a workable order under
normal operating conditions, with nothing enforcing that order explicitly,
until a full restart lets the race actually play out the wrong way. It's
also a classic multi-node cluster problem — a fleet-wide reboot (patching,
a datacenter power event, a mass instance restart in a cloud provider) is
exactly the scenario where every node hits the race simultaneously,
turning an invisible one-off bug into a fleet-wide outage. The fix in
both this lab's main scenario and Challenge B is the same discipline:
declare real dependencies (`Requires=`/`After=`, `RequiresMountsFor=`)
explicitly rather than relying on incidental timing, and validate
boot-time config (fstab entries, unit dependency graphs) immediately after
editing rather than waiting for the next reboot to find out.

## Go deeper

- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man5/systemd.unit.5.html — canonical documentation for `After=`/`Before=`/`Requires=`/`Wants=`/`RequiresMountsFor=` semantics.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man5/systemd.service.5.html — service unit specifics, including `Type=`/`Restart=` behavior relevant to this lab.
- **Website/docs:** Arch Linux Wiki — https://wiki.archlinux.org — has excellent, precise pages on systemd unit dependencies, targets, and fstab/mount-unit generation.
- **Website/docs:** Linux kernel docs / freedesktop systemd docs — https://docs.kernel.org — for background on boot targets and unit ordering, cross-referenced with the man pages above.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — has dedicated systemd unit dependency and troubleshooting walkthroughs.
