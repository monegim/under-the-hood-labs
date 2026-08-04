# Lab 25 — Concept: TLS Handshake Failures

## What's actually going on

A TLS handshake is a negotiation with several independent things that all
have to succeed, in order, before any application data moves: the client
and server have to agree on a protocol version, then agree on a cipher
suite (for TLS 1.2 and earlier, this includes key exchange, authentication,
bulk cipher, and MAC algorithm all bundled into one named suite; TLS 1.3
narrows this to just an AEAD cipher and a hash, since key exchange is
handled separately via (EC)DHE and always forward-secret), and only after
both of those succeed does certificate presentation and verification even
happen. When a handshake fails, the TLS alert protocol tells you — if
you're reading it — *which* of these steps failed, because the alert type
is specific to the failure reason. Alert 70, `protocol_version`, means the
two sides had zero TLS versions in common — this lab's Step 6, a server
hardened to `TLSv1.3` only rejecting a client that can't go above TLS 1.2,
happens before any cipher or certificate discussion is even possible.
Alert 40, `handshake_failure`, is the generic "we agreed on a version but
couldn't agree on anything else" alert — most commonly, as in Step 8, zero
cipher suite overlap. Both alerts look identical from a distance ("the
handshake failed"), and both require completely different fixes — which
is the entire reason this lab has you read the actual alert number instead
of just noticing that `openssl s_client` printed an error.

TLS 1.3's redesign of cipher negotiation is itself a real, common source of
confusion, and Challenge B is built directly around it. Every cipher suite
name you'd recognize from TLS 1.2 troubleshooting (`ECDHE-RSA-AES256-GCM-
SHA384` and similar) belongs to a completely different negotiation
mechanism than TLS 1.3 uses. Nginx (following OpenSSL's own API split)
exposes these as two separate configuration surfaces: `ssl_ciphers` feeds
`SSL_CTX_set_cipher_list()`, which only ever governs TLS 1.2 and earlier;
TLS 1.3's cipher suites are configured through `ssl_conf_command
Ciphersuites ...`, feeding the newer `SSL_CTX_set_ciphersuites()` API.
Neither directive has any effect on the other version's negotiation — a
config change to `ssl_ciphers` will reload cleanly, look correct, and
simply never be consulted for a TLS 1.3 connection, which is exactly why
Challenge B's "fix" does nothing measurable until you find the directive
that's actually in the TLS 1.3 code path.

SNI (Server Name Indication) is a different mechanism entirely from either
of the above, and Challenge A is built to make that distinction
unmistakable: SNI is sent unencrypted at the very start of the ClientHello,
before any cipher or version negotiation outcome is even relevant, purely
so a server hosting multiple certificates on one IP/port (this lab's two
vhosts on port 443) knows which certificate to present. Critically, SNI
selection is not the same thing as SNI *validation* — nginx will happily
complete a full, successful handshake using whatever server block it picks
(falling back to `default_server` when nothing matches), even if the
resulting certificate has nothing to do with the hostname that was
requested. The client is the only party positioned to catch that mismatch,
by comparing the returned certificate's subject/SAN against the hostname
it meant to reach — which is exactly what certificate hostname
verification does in a real browser or HTTP client, and exactly what
`openssl s_client` does *not* do for you automatically.

## Where this shows up in the real world

- A server-side TLS hardening pass (disabling TLS 1.0/1.1, sometimes 1.2)
  rolled out without an inventory of what's actually connecting — internal
  service-to-service clients, older load balancer health checks, legacy
  IoT/embedded devices — is one of the most common self-inflicted outages
  in production TLS changes, and it produces exactly this lab's Step 6
  alert on every affected client simultaneously.
- Multi-tenant reverse proxies and CDNs serving many hostnames off shared
  IPs depend entirely on SNI-based certificate selection; a newly
  onboarded hostname that hasn't had its vhost/certificate deployed yet
  falling through to some *other* tenant's certificate (this lab's
  Challenge A) is a realistic, security-relevant misconfiguration, not
  just a lab contrivance.
- **Diagnosis scenario:** "some clients can connect, others get TLS
  errors, the certificate is valid and not expired" is the signature this
  entire lab is built around — `openssl s_client -connect host:port
  -tls1_2` / `-tls1_3` against the affected endpoint, read for the
  specific alert name/number, separates a version problem from a cipher
  problem from a routing/SNI problem in one command, versus hours spent
  re-checking certificate expiry that was never the issue.

## Go deeper
- **Website/docs:** OpenSSL docs — https://www.openssl.org/docs/ — canonical reference for `s_client`, TLS alert types, and the cipher list vs ciphersuite API split (`SSL_CTX_set_cipher_list` vs `SSL_CTX_set_ciphersuites`) this lab's Challenge B is built around.
- **Book:** *TCP/IP Illustrated, Volume 1* — W. Richard Stevens (updated by Kevin Fall) — foundational transport/session-layer material that the TLS handshake sits directly on top of.
- **Website/docs:** NetworkLessons.com — https://networklessons.com — structured tutorials covering the TLS handshake sequence and where version/cipher negotiation fits into it.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/ — general Linux reference for the underlying networking primitives (sockets, `ip-address(8)`) used to wire up this lab's topology.
