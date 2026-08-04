# Lab 21 — Clock Drift (NTP/chrony)

## Objective
Let a system clock drift 60 days out of sync while `chronyd` sits stopped
and masked, then diagnose a TLS failure that has nothing to do with the
certificate itself.

## Why this matters
"Certificate expired" is one of the most common false leads in
production troubleshooting. The cert can be perfectly valid — if the
client or server's clock is wrong, every certificate looks expired (or
not-yet-valid) to it. The same root cause (a drifted, unsynced clock)
also silently breaks Kerberos/SSO auth, JWT `exp`/`iat` validation, and
makes log timestamps across hosts impossible to correlate during an
incident. Nobody thinks to check `chronyc tracking` until they've already
wasted twenty minutes staring at a cert that's fine.

## Prerequisites
- A disposable/test Linux VM — **this lab changes the whole-system
  clock**, not something sandboxed. Do not run it on a shared or
  production box.
- `sudo` access

Check first:
```bash
chronyc tracking
timedatectl
```

## Step 1 — Build the incident
```bash
sudo bash setup.sh
```
This installs `chrony`/`openssl`, generates a genuinely valid TLS
certificate (valid now, for 30 days), starts a local HTTPS test endpoint
on `:8443` using it, then stops and masks `chronyd`, disables NTP sync,
and jumps the system clock 60 days into the future.

## Step 2 — Observe the (misleading) symptom
```bash
curl -v https://localhost:8443/ 2>&1 | grep -i -A2 certificate
```
> Gotcha: the error will say the certificate has expired or isn't valid
> yet — read literally, that points you at the cert. Check the cert's
> own recorded validity window before you believe that:
> ```bash
> cat /var/tmp/lab21_cert_dates.txt
> ```
> It's still well within its 30-day window. The clock is wrong, not the
> cert.

## Step 3 — Confirm it's the clock
```bash
date
chronyc tracking
systemctl status chrony
```
`chronyc tracking` will either fail to reach a masked/stopped daemon, or
(once it's running) show a leap status and a large system time offset —
that offset, not the certificate, is the actual root cause.

## Step 4 — Fix it
```bash
sudo systemctl unmask chrony
sudo timedatectl set-ntp true
sudo systemctl restart chrony
sudo chronyc makestep
```
`chronyc makestep` forces an immediate clock step instead of chrony's
normal slow slew, since a 60-day offset would otherwise take a very long
time to correct gradually.

## Step 5 — Confirm the fix
```bash
date
chronyc tracking
curl -s https://localhost:8443/ -o /dev/null && echo "TLS OK"
```

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A:**
```bash
sudo cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.lab21.bak
echo "server 192.0.2.1 iburst" | sudo tee -a /etc/chrony/chrony.conf
sudo systemctl restart chrony
```
`chronyd` is running, unmasked, NTP is enabled — and it's still never
correcting. `192.0.2.1` is a TEST-NET address (RFC 5737), guaranteed
unreachable. `systemctl status chrony` looks fine. What does `chronyc
sources` show that `systemctl status` doesn't?

**Challenge B:**
```bash
sudo iptables -A OUTPUT -p udp --dport 123 -j DROP
```
This looks like the same symptom as Challenge A — chrony configured
correctly, still not syncing — but it's a different layer of failure
entirely. What's the difference in what `chronyc sources` reports
between "server is unreachable" (A) and "server traffic is being
dropped" (B), and what tool would show you the second one directly?

See `solution.md` only after you've formed your own diagnosis.
