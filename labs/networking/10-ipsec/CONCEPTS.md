# Lab 10 — Concept: IPsec, IKE Phases, and Why "Won't Connect" Has More Than One Cause

## What's actually going on

IPsec is really two separable pieces working together: a control-plane
protocol (IKE) that negotiates and authenticates a shared session, and a
data-plane protocol (ESP, IP protocol 50, which is exactly what you saw in
the `tcpdump -c 5 esp` capture) that actually encrypts and authenticates
traffic once the session exists. strongSwan's `charon` daemon implements
IKE; the kernel's **xfrm** framework (`ip xfrm state`, `ip xfrm policy`)
is what actually does the per-packet encryption/decryption and enforces
which traffic gets protected — charon negotiates keys and policy, then
programs them into xfrm, and the kernel data path does the rest without
charon in the loop for every packet.

IKEv2 negotiation happens in distinct, ordered phases, and *which phase
fails* is the single most diagnostic fact in a broken tunnel — this is the
entire point of contrasting Challenges A and B. **IKE_SA_INIT** comes
first: an unauthenticated Diffie-Hellman exchange whose only job is to
stand up a secure channel for the next message. It doesn't touch the PSK
or any identity at all — it's pure key agreement. **IKE_AUTH** comes next,
and this is where each side actually proves who it is, using the
pre-shared key (or certificates) to compute an authentication payload the
other side verifies. When r2's PSK was changed (Challenge A), IKE_SA_INIT
completes fine — the DH exchange doesn't care about secrets — but IKE_AUTH
fails with `AUTHENTICATION_FAILED`, because the payload r1 computed no
longer matches what r2 (with the wrong secret) expects. Only after
IKE_AUTH succeeds does IKE negotiate the actual **CHILD_SA** — the ESP
tunnel itself, including which encryption/authentication algorithms to
use. Challenge B's algorithm mismatch (`aes256-sha256!` vs `aes128-sha1!`)
lets IKE_SA_INIT *and* IKE_AUTH both succeed — authentication was never
the problem — and only fails at this last stage, with `NO_PROPOSAL_CHOSEN`,
because the trailing `!` in strongSwan config syntax means "this exact
proposal, no fallback," so the two sides' offered transform sets don't
intersect at all. Two failures that both present as "tunnel won't come
up" are actually happening at completely different points in a
three-phase negotiation, which is exactly why the charon log — not just
"did it connect" — is the thing worth reading.

`leftsubnet`/`rightsubnet` matter because this lab uses **policy-based**
IPsec, the classic and still extremely common site-to-site pattern: the
kernel's Security Policy Database (SPD, visible via `ip xfrm policy`)
matches outbound packets against subnet/protocol selectors and decides
whether to send them through the IPsec transform or in the clear. If you
omit `leftsubnet`/`rightsubnet`, they default to the gateway addresses
themselves — you'd get a tunnel that only protects `r1`-to-`r2` traffic,
while real hostA-to-hostB LAN traffic, which is what you actually wanted
protected, just routes past it unencrypted because it never matches the
narrow policy. (The alternative model, route-based/VTI, represents the
tunnel as a virtual interface and lets ordinary routing decide what goes
through it — different mechanism, same underlying ESP/IKE machinery
underneath.)

## Where this shows up in the real world

Every "site-to-site VPN" you click "connect" on in a cloud console — AWS
Site-to-Site VPN, Azure VPN Gateway, GCP Cloud VPN — is IPsec under the
hood, usually IKEv2 with a PSK exactly like this lab, sometimes with BGP
running over the tunnel for dynamic routing. Production IPsec outages are
overwhelmingly one of: a secret/algorithm mismatch between the two ends
(this lab's two challenges), or a forgotten/incorrect subnet definition
silently leaving some traffic unprotected or unreachable (this lab's
`leftsubnet`/`rightsubnet` gotcha). An engineer who knows to check which
negotiation phase a failing tunnel actually reached can tell a secret
problem from a cipher-suite problem from the log alone, in minutes,
instead of guessing between "check the PSK" and "check the proposal" and
trying both blind.

## Go deeper

- **Website/docs:** strongSwan docs — https://docs.strongswan.org — the authoritative reference for `ipsec.conf` syntax, IKEv2 phases, and reading charon logs.
- **Book:** *TCP/IP Illustrated, Volume 1* — W. Richard Stevens (updated by Kevin Fall) — protocol-internals-level treatment of the IP layer that ESP/AH sit on top of.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/ — `ip-xfrm(8)` documents the kernel's Security Policy/Security Association Database model used by every IPsec implementation on Linux.
- **Website:** ipSpace.net — https://ipspace.net — Ivan Pepelnjak has deep-dive material on VPN/IPsec design tradeoffs (policy-based vs route-based, IKEv1 vs IKEv2).
- **YouTube:** David Bombal — https://www.youtube.com/@davidbombal — has IPsec/VPN configuration and troubleshooting walkthroughs.
