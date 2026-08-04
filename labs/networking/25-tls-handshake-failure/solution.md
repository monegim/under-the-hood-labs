# Lab 25 — Solutions

## Challenge A — SNI mismatch: a successful handshake, the wrong certificate

**Check:**
```bash
docker exec clab-tls-lab-client openssl s_client -connect 10.99.0.2:443 \
  -servername unknown.example.test </dev/null 2>/dev/null | openssl x509 -noout -subject
```
Output: `subject=CN = correct.example.test` — even though the request was
for `unknown.example.test`, which was never configured as a `server_name`
anywhere.

**Diagnosis:** SNI (Server Name Indication) is sent in the clear during
the TLS ClientHello, and nginx uses it purely to pick *which configured
server block* to hand the connection to — it's a routing decision, not a
validation. `unknown.example.test` doesn't match either configured
`server_name`, so nginx falls back to whichever server block is marked
`default_server` on that `listen` directive — in this lab, that's
`correct.example.test`'s block. Nginx has no concept of "reject this
because the SNI doesn't match" — it happily completes a perfectly valid
TLS handshake using the default block's certificate, for literally any
SNI value a client sends. The mismatch is entirely the client's problem to
catch, by comparing the certificate it actually received against the
hostname it meant to reach — which is exactly what browsers and properly
configured HTTP clients do (and why they'd show a certificate name
mismatch warning here), but `openssl s_client` on its own does not check
this for you.

**Fix (there isn't one to "fix" here architecturally — this is nginx
behaving correctly; the fix is on whichever side got the hostname wrong):**
```bash
# if unknown.example.test should have its own vhost/cert, add one:
docker exec clab-tls-lab-proxy openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /etc/nginx/certs/unknown.key -out /etc/nginx/certs/unknown.crt \
  -subj "/CN=unknown.example.test"
# ...and a matching server block with server_name unknown.example.test;

# if the client was simply requesting the wrong name, fix the client instead
```

**Lesson:** a successful TLS handshake proves the server was willing to
negotiate — it proves nothing about whether the certificate it handed back
actually belongs to the name you asked for. This is precisely why hostname
verification is a separate, mandatory step in every correct TLS client
implementation, not an optional extra: without it, "SNI didn't match
anything configured" degrades silently into "here's someone else's
certificate" instead of a clear error, and `openssl s_client` alone will
show you that without complaint.

---

## Challenge B — `ssl_ciphers` restricted, TLS 1.3 unaffected

**Check:**
```bash
docker exec clab-tls-lab-client curl -k --tlsv1.3 --tls-max 1.3 \
  --resolve correct.example.test:443:10.99.0.2 https://correct.example.test/ -v 2>&1 | grep -i cipher
```
The connection succeeds and negotiates a TLS 1.3 AEAD cipher suite
(something like `TLS_AES_256_GCM_SHA384`) despite `ssl_ciphers` being
pinned to `ECDHE-RSA-AES256-GCM-SHA384` — a cipher suite name that isn't
even a valid TLS 1.3 ciphersuite name at all.

**Diagnosis:** `ssl_ciphers` in nginx (and the underlying OpenSSL
`SSL_CTX_set_cipher_list()` API it calls) only ever controlled cipher
suite selection for TLS 1.2 and earlier. TLS 1.3 redesigned cipher suite
negotiation, deliberately narrowed it down to a small, all-AEAD, forward-
secret-by-default list, and OpenSSL exposes configuring *that* list
through a completely separate API (`SSL_CTX_set_ciphersuites()`), which
nginx surfaces via `ssl_conf_command Ciphersuites ...`, not via
`ssl_ciphers`. Setting `ssl_ciphers` to something narrow only ever
constrained what Step 8's TLS-1.2 connection could negotiate — it was
never in the TLS 1.3 code path to begin with, which is exactly why
tightening or loosening it never changed Step 9's TLS 1.3 result at all.

**Fix:**
```bash
docker exec -i clab-tls-lab-proxy bash -c "sed -i '/ssl_ciphers/a\\    ssl_conf_command    Ciphersuites TLS_AES_128_GCM_SHA256;' /etc/nginx/conf.d/default.conf"
docker exec clab-tls-lab-proxy nginx -s reload
docker exec clab-tls-lab-client curl -k --tlsv1.3 --tls-max 1.3 \
  --resolve correct.example.test:443:10.99.0.2 https://correct.example.test/
```
*This* is the directive that actually constrains TLS 1.3, and restricting
it to a single suite the client doesn't independently support would
reproduce Step 8's `handshake_failure` alert, but for a TLS 1.3 session
instead of TLS 1.2.

**Lesson:** "cipher suite configuration" is not one setting across TLS
versions — TLS 1.3's cipher suite list is configured through an entirely
different directive than everything before it, and editing the wrong one
produces a config change that looks correct, reloads without error, and
does absolutely nothing for the connections you were actually trying to
affect. Always confirm *which* directive governs the TLS version you're
actually troubleshooting before concluding a config change "didn't work."
