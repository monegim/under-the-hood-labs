# Lab 21 — Concept: Clock Sync, NTP/chrony, and Why TLS Depends On It

## What's actually going on

Every Linux system keeps time using a combination of a hardware clock
(the RTC, battery-backed, keeps ticking when the machine is off) and a
software clock maintained by the kernel while it's running. Left alone,
the software clock drifts — crystal oscillators are cheap and imprecise,
and a few seconds of drift per day is completely normal physics, not a
bug. NTP (and its modern, more accurate implementation, chrony) exists
entirely to correct that drift by periodically comparing the local clock
against a remote reference and adjusting.

`chronyd` does this in two different ways depending on how far off the
clock is. For small offsets (the normal, expected case), it *slews* the
clock — speeding it up or slowing it down slightly so it converges on the
correct time smoothly, without ever running backwards (which would
confuse anything relying on monotonically increasing timestamps). For
large offsets — like the 60-day jump this lab creates — chrony by default
won't slew (it would take far too long), and depending on
`makestep`/`maxchange` settings in `chrony.conf`, it either refuses to
correct automatically at all or requires an explicit step. That's why
`chronyc makestep` exists: it's the "just set it, don't ease into it"
command, appropriate for exactly this kind of gross drift.

The reason this lab picks TLS as the symptom is that X.509 certificate
validation is fundamentally a clock-dependent operation. Every
certificate carries a `notBefore` and `notAfter` field, and the TLS
library validating it does nothing more sophisticated than compare those
against the *local* system clock — it has no independent way to know
what time it "really" is. If the local clock is wrong, a certificate that
is completely valid by any external reference will be rejected as
expired or not-yet-valid, and the error message will say exactly that,
pointing you straight at the wrong subsystem. This is not a TLS bug; it's
TLS working exactly as designed, fed bad input. The same mechanism breaks
Kerberos ticket validation (tickets have tight time-skew tolerances,
often 5 minutes, specifically to limit replay-attack windows) and JWT
`exp`/`iat`/`nbf` claim validation — anything built on "prove this token
was issued/is still valid within a time window" inherits clock dependence
whether its author thought about it or not.

`chronyc tracking`'s output distinguishes several things worth knowing:
`Leap status` (Normal/Insert second/Delete second/Not synchronised) tells
you if chrony considers itself synced at all; `System time` gives the
current offset from chrony's best estimate of correct time; and
`chronyc sources -v` shows each configured time source individually —
critically, a source can be configured and the daemon can be running
while that specific source has never successfully answered a single
poll, which is invisible from `systemctl status` alone.

## Where this shows up in the real world

This is a disproportionately common root cause behind "random" TLS
failures in fleets of VMs or containers, especially ones that don't have
reliable outbound NTP access (locked-down egress firewalls, VMs cloned
from a template with a frozen/wrong initial clock, hypervisors that don't
properly sync guest clocks). It's also a classic multi-host debugging
trap: when comparing logs across two hosts to reconstruct an incident
timeline, if either host's clock is off, events that actually happened in
one order can appear to have happened in a different, causally impossible
order — and unless you think to check `chronyc tracking` on both hosts
first, you can burn a lot of time trying to explain a timeline that was
never real.

## Go deeper

- **Book:** *The Linux Programming Interface* — Michael Kerrisk. Covers the kernel's timekeeping model and the syscalls (`clock_gettime`, `adjtimex`) that NTP/chrony daemons are actually built on.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man5/chrony.conf.5.html — the authoritative reference for `chrony.conf` directives including `makestep`/`maxchange`, and https://man7.org/linux/man-pages/man1/chronyc.1.html for every `chronyc` subcommand.
- **Website/docs:** Arch Wiki — https://wiki.archlinux.org — has one of the clearest practical writeups of chrony configuration and troubleshooting available for free, distro-specifics aside.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV — search their channel for systemd-timesyncd/chrony content; they cover Linux time synchronization as part of broader systemd administration videos.
