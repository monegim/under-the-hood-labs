# Lab 25 — TLS Handshake Failure

## Objective
Build an nginx reverse proxy hardened to modern TLS settings, then produce
two genuinely different flavors of handshake failure — a protocol-version
mismatch and a cipher-suite mismatch — plus a third failure that isn't a
handshake failure at all: a successful handshake that serves the *wrong*
certificate. Learn to tell all three apart from `openssl s_client` output
alone.

## Why this matters
"The cert expired" is the TLS failure everyone already knows how to
diagnose. The failures that actually eat hours in production are the ones
where the certificate is completely fine and the connection still won't
complete: a server hardened to TLS 1.3-only rejecting a client stuck on
TLS 1.2, a cipher-suite allowlist that's technically correct but has zero
overlap with what a particular client offers, or a reverse proxy silently
serving one vhost's certificate for a hostname it was never issued for.
Each of these produces a different, specific alert during the handshake —
and reading which one you got is the difference between fixing it in
minutes and guessing for an hour.

## Prerequisites
- Docker + [containerlab](https://containerlab.dev) installed
- `nginx` and `nicolaka/netshoot` images pulled

Check first:
```bash
docker version
containerlab version
docker pull nginx:latest
docker pull nicolaka/netshoot:latest
```

## Step 1 — Deploy the topology
```bash
sudo containerlab deploy -t topology.clab.yml
```

## Step 2 — Address the link
```bash
docker exec clab-tls-lab-client ip addr add 10.99.0.1/24 dev eth1
docker exec clab-tls-lab-client ip link set eth1 up

docker exec clab-tls-lab-proxy ip addr add 10.99.0.2/24 dev eth1
docker exec clab-tls-lab-proxy ip link set eth1 up

docker exec clab-tls-lab-client ping -c 2 10.99.0.2
```

## Step 3 — Install openssl and generate two self-signed certificates
```bash
docker exec clab-tls-lab-proxy sh -c "apt-get update -qq && apt-get install -y -qq openssl >/dev/null"

docker exec clab-tls-lab-proxy mkdir -p /etc/nginx/certs
docker exec clab-tls-lab-proxy openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /etc/nginx/certs/correct.key -out /etc/nginx/certs/correct.crt \
  -subj "/CN=correct.example.test"
docker exec clab-tls-lab-proxy openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /etc/nginx/certs/other.key -out /etc/nginx/certs/other.crt \
  -subj "/CN=other.example.test"
```

## Step 4 — Configure nginx: two vhosts, hardened to TLS 1.3 only
```bash
docker exec -i clab-tls-lab-proxy bash -c "cat > /etc/nginx/conf.d/default.conf" <<'EOF'
server {
    listen 443 ssl default_server;
    server_name correct.example.test;

    ssl_certificate     /etc/nginx/certs/correct.crt;
    ssl_certificate_key /etc/nginx/certs/correct.key;
    ssl_protocols       TLSv1.3;

    location / { return 200 "ok - served by correct.example.test vhost\n"; }
}

server {
    listen 443 ssl;
    server_name other.example.test;

    ssl_certificate     /etc/nginx/certs/other.crt;
    ssl_certificate_key /etc/nginx/certs/other.key;
    ssl_protocols       TLSv1.3;

    location / { return 200 "ok - served by other.example.test vhost\n"; }
}
EOF

docker exec clab-tls-lab-proxy nginx -s reload
```
> `default_server` on the first block matters for the Challenges later —
> it's what nginx falls back to when a client's requested SNI doesn't
> match any configured `server_name`.

## Step 5 — Confirm the healthy baseline
```bash
docker exec clab-tls-lab-client curl -k --resolve correct.example.test:443:10.99.0.2 \
  https://correct.example.test/
```
Modern `curl`/OpenSSL defaults to trying TLS 1.3 first — this succeeds.

## Step 6 — Simulate an old client stuck on TLS 1.2
```bash
docker exec clab-tls-lab-client openssl s_client -connect 10.99.0.2:443 \
  -servername correct.example.test -tls1_2 </dev/null
```
This fails. Look for a line resembling:
```
...:error:...:SSL routines:...:tlsv1 alert protocol version:...
```
and, further down, `SSL alert number 70`. Alert 70 is `protocol_version` —
the client and server never even agreed on *which version* of TLS to
speak; nothing about ciphers or certificates was ever reached.

## Step 7 — Fix the version mismatch
```bash
docker exec -i clab-tls-lab-proxy bash -c "sed -i 's/ssl_protocols       TLSv1.3;/ssl_protocols       TLSv1.2 TLSv1.3;/' /etc/nginx/conf.d/default.conf"
docker exec clab-tls-lab-proxy nginx -s reload

docker exec clab-tls-lab-client openssl s_client -connect 10.99.0.2:443 \
  -servername correct.example.test -tls1_2 </dev/null
```
Succeeds now. Worth saying out loud: allowing TLS 1.2 back in is a real
security tradeoff, made here to keep an old client working *today* — the
actual fix in most real incidents is upgrading whatever's stuck on TLS
1.2, not permanently lowering the server's floor. Treat this as a
temporary compatibility bridge, not the end state.

## Step 8 — A second, different mismatch: ciphers, not versions
```bash
docker exec -i clab-tls-lab-proxy bash -c "sed -i '/ssl_protocols       TLSv1.2 TLSv1.3;/a\\    ssl_ciphers         ECDHE-RSA-AES256-GCM-SHA384;' /etc/nginx/conf.d/default.conf"
docker exec clab-tls-lab-proxy nginx -s reload

docker exec clab-tls-lab-client openssl s_client -connect 10.99.0.2:443 \
  -servername correct.example.test -tls1_2 -cipher AES128-SHA </dev/null
```
Fails again — but read the alert closely, it's a *different* one this
time:
```
...:SSL alert number 40
```
Alert 40 is `handshake_failure`, not `protocol_version`. Both sides agreed
on TLS 1.2 just fine this time (no version alert) — they simply have zero
cipher suites in common: the server will only accept
`ECDHE-RSA-AES256-GCM-SHA384`, the client only offered the legacy
`AES128-SHA`. Same "handshake failed" headline, completely different root
cause and completely different fix.

## Step 9 — Fix the cipher mismatch
```bash
docker exec -i clab-tls-lab-proxy bash -c "sed -i 's/ssl_ciphers         ECDHE-RSA-AES256-GCM-SHA384;/ssl_ciphers         HIGH:!aNULL:!MD5:!3DES;/' /etc/nginx/conf.d/default.conf"
docker exec clab-tls-lab-proxy nginx -s reload

docker exec clab-tls-lab-client curl -k --tlsv1.2 --tls-max 1.2 \
  --resolve correct.example.test:443:10.99.0.2 https://correct.example.test/
docker exec clab-tls-lab-client curl -k --tlsv1.3 --tls-max 1.3 \
  --resolve correct.example.test:443:10.99.0.2 https://correct.example.test/
```
Both succeed — a broad modern cipher list has enough overlap with both an
old TLS 1.2 client and a fully current TLS 1.3 one.

## Challenges

**Challenge A:**
```bash
docker exec clab-tls-lab-client openssl s_client -connect 10.99.0.2:443 \
  -servername unknown.example.test </dev/null 2>/dev/null | openssl x509 -noout -subject
```
The handshake **succeeds** — no alert, no error, nothing that looks like
Steps 6 or 8's failures at all. Compare the certificate `subject` this
prints against the hostname you actually asked for
(`unknown.example.test`). Something is clearly wrong here even though
nothing failed — work out what, and why a successful handshake was even
possible for a hostname that was never configured at all.

**Challenge B:**
```bash
docker exec -i clab-tls-lab-proxy bash -c "sed -i 's/ssl_ciphers         HIGH:!aNULL:!MD5:!3DES;/ssl_ciphers         ECDHE-RSA-AES256-GCM-SHA384;/' /etc/nginx/conf.d/default.conf"
docker exec clab-tls-lab-proxy nginx -s reload

docker exec clab-tls-lab-client curl -k --tlsv1.3 --tls-max 1.3 \
  --resolve correct.example.test:443:10.99.0.2 https://correct.example.test/
```
This re-applies Step 8's narrow, TLS-1.2-oriented `ssl_ciphers` value —
and the TLS 1.3 connection still succeeds anyway, completely unaffected.
If `ssl_ciphers` really controls which ciphers are acceptable, why didn't
restricting it to one specific cipher break a TLS 1.3 connection the way
it broke TLS 1.2 in Step 8? What does this tell you about what
`ssl_ciphers` actually configures, and what would you need to change
instead to control TLS 1.3's cipher suite selection specifically?

See `solution.md` only after you've formed your own diagnosis.
