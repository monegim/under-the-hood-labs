# Incident 02 — The Hanging API Calls

## The page

> Support is escalating a handful of tickets: "report generation" is
> timing out for a few specific enterprise customers, while it works
> fine for everyone else. Health checks are green. There's nothing in
> the application logs or the database's error log. It's been going on
> since a routine firewall change last week.

No stack trace, no 5xx spike dashboard - just "it's slow/broken for some
customers, not others," which is exactly the kind of ticket that gets
handed to whoever's on call with "probably the database, can you look?"

## Environment

A small two-tier deployment:
- `api` - a report-generation service that queries a MySQL database for
  a given customer's order history and returns it.
- `db` - the MySQL database.
- The two sides talk to each other over a site-to-site link (a GRE
  tunnel between two routers, `r1` and `r2`) - the kind of setup you'd
  see between an app tier and a database tier in different network
  segments, availability zones, or a colo migration in progress.

You have `docker exec` access into every node (`api`, `r1`, `r2`, `db`),
and the usual tools: `curl`, `tcpdump`, `ping`, `iptables`, `ip`, `mysql`
client.

## Your task

Find the root cause and fix it. Use whatever tools you'd normally reach
for (`curl`, `tcpdump`, `ping`, `mysql` client, `iptables -L -v`, etc.).
There's no prescribed sequence - explore the environment the way you
would a real page.

## Getting unstuck

- "Works for most customers, fails for a few specific ones" - what's
  actually different about those customers' data versus everyone
  else's? Is it about *who* they are, or about the *size* of what gets
  returned for them?
- If a request just hangs and eventually times out, with literally
  nothing showing up in either service's logs, the failure probably
  isn't happening in the application or the database at all - which
  layer does that leave?
- A packet capture on either side of the link, while reproducing the
  failing request, will show you more in thirty seconds than an hour of
  reading logs. Compare what a *working* request looks like on the wire
  against what a *failing* one looks like.

See `solution.md` only after you've formed your own diagnosis, or if
you're completely stuck after trying the nudges above.
