# Lab 17 — Solutions

## Challenge A — PSK mismatch

**Check:**
```bash
docker exec clab-ipsec-lab-r1 ipsec statusall
```
`site-to-site` never reaches `ESTABLISHED`. The charon log shows the
IKE_SA_INIT exchange complete (both sides agreed on a Diffie-Hellman group
and did the initial key exchange fine), then an `AUTHENTICATION_FAILED`
notify during IKE_AUTH.

**Diagnosis:** IKE_SA_INIT doesn't involve the PSK at all — it's an
unauthenticated DH exchange to set up a secure channel for the *next*
message. Authentication (proving each side is who it claims, using the
shared secret) happens in IKE_AUTH, one step later. Since r2's
`ipsec.secrets` now has a different PSK than r1's, the computed
authentication payload doesn't match what the other side expects, and the
peer rejects it outright.

**Fix:**
```bash
docker exec clab-ipsec-lab-r2 sed -i 's/wrongpsk/supersecretpsk/' /etc/ipsec.secrets
docker exec clab-ipsec-lab-r2 ipsec rereadsecrets
docker exec clab-ipsec-lab-r1 ipsec up site-to-site
```

**Lesson:** IKE negotiation happens in distinct phases (SA_INIT, then
AUTH, then CHILD_SA), and *how far the negotiation got before failing* is
the single most useful piece of information in the log — it tells you
whether you're looking at a reachability problem (never gets to SA_INIT), an
identity/secret problem (fails at AUTH), or a cryptographic proposal
problem (fails at CHILD_SA negotiation, see Challenge B).

---

## Challenge B — proposal (algorithm) mismatch

**Check:**
```bash
docker exec clab-ipsec-lab-r1 ipsec statusall
```
Again fails to reach a full `ESTABLISHED` state with an active IPsec SA.
The charon log this time shows IKE_SA_INIT *and* IKE_AUTH complete (so
authentication succeeded — the PSK matched fine), but the CHILD_SA (the
actual ESP tunnel) negotiation fails with a `NO_PROPOSAL_CHOSEN` notify.

**Diagnosis:** r1 is offering `esp=aes256-sha256!` while r2 now offers
`esp=aes128-sha1!`. The trailing `!` makes each side's proposal strict —
strongSwan won't silently fall back to a common subset, it just rejects
the CHILD_SA request outright when the offered ESP transforms don't
overlap. Unlike Challenge A, authentication itself was never the problem —
the two sides just can't agree on how to actually encrypt traffic.

**Fix:**
```bash
docker exec clab-ipsec-lab-r2 sed -i 's/esp=aes128-sha1!/esp=aes256-sha256!/' /etc/ipsec.conf
docker exec clab-ipsec-lab-r2 ipsec reload
docker exec clab-ipsec-lab-r1 ipsec up site-to-site
```

**Lesson:** "PSK mismatch" and "algorithm mismatch" both present as "tunnel
won't come up," but they fail at different negotiation phases and produce
different notify messages (`AUTHENTICATION_FAILED` vs `NO_PROPOSAL_CHOSEN`)
— read the actual log line instead of guessing between "check the secret"
and "check the proposal."
