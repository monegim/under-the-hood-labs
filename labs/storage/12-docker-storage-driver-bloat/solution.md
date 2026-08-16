# Lab 12 — Solutions

## Challenge A — `image prune -a` removes tagged-but-unused images too

**Check:**
```bash
sudo docker -H unix:///var/run/dockerlab.sock images
```
Before `-a`: only dangling (untagged, `<none>`) images are gone after
Step 5's plain `image prune`. After `image prune -a -f`: the image list
shrinks further — tagged images (like older versions of this lab's
sample app image) with no container currently running from them are now
gone too, not just the untagged ones.

**Diagnosis:** plain `docker image prune` (no `-a`) only ever removes
**dangling** images — layers with no tag pointing at them at all, which
is about as unambiguous "nobody could possibly want this by name" as
Docker can determine on its own. `docker image prune -a` expands the
definition of "unused" dramatically: it removes any image, tagged or
not, that no container (running or stopped) currently references. That
includes a perfectly valid, tagged image like `myapp:v1.2` sitting
around specifically so a rollback or a currently-scaled-to-zero service
can start from it again without a rebuild — from Docker's point of view,
"not currently backing a container" and "safe to delete" are treated as
the same thing under `-a`, even though operators very often keep tagged
images around for exactly the case where nothing is using them *right
now*.

**Fix:** there's no "undo" beyond re-pulling or rebuilding the removed
image. The actual fix is process, not a command: know the difference
before running either form, and reserve `-a` for hosts where you're
certain every image that matters is either currently running or
reproducible on demand (a build server, not a host you might need to
roll back on).

**Lesson:** `-a` is not "prune more aggressively" in a generic sense —
it specifically changes *what counts as unused* to include tagged
images, which is a materially different, much broader class of "safe to
delete" than dangling-only. Read `docker image prune --help` for exactly
this distinction before scripting either form into a cron job.

---

## Challenge B — a volume is only protected while something references it right now

**Check:**
```bash
sudo docker -H unix:///var/run/dockerlab.sock volume ls
```
After `stop` alone, `dockerlab_appdata` is still listed — a stopped
container still holds a reference to its mounted volumes. Only after
`rm` (removing the container itself, not just stopping it) does the
volume become unreferenced by anything. The subsequent
`system prune -a -f --volumes` then removes it, along with
`marker.txt`'s contents, permanently.

**Diagnosis:** two separate things both had to be true for the volume to
be deleted. First, the container had to be actually removed
(`docker rm`), not just stopped — Docker considers a stopped-but-present
container's volume mounts as still "in use," which is why `stop` alone
changed nothing about `volume ls`. Second, `--volumes` had to be passed
explicitly — this is a deliberate Docker safety default: **plain**
`docker system prune`, even with `-a`, never touches volumes at all
unless `--volumes` is added on top. Both defaults exist specifically to
make volume deletion something you have to opt into twice, not
something that happens as a side effect of a routine image/container
cleanup. The part that makes this genuinely dangerous in practice is how
ordinary "container recreated against the same named volume, nothing is
attached to it for a few seconds" is during a completely normal deploy
(`docker rm old-container && docker run --name new-container -v
dockerlab_appdata:/data ...`) — the exact moment `system prune
--volumes` catches a persistent-data volume "unused" is a state most
volumes pass through routinely and briefly, not a sign the volume is
actually disposable.

**Fix:** nothing recovers `marker.txt`'s content once the volume backing
it is removed — the fix here is prevention: never run `--volumes` as
part of a routine or scheduled cleanup without first confirming (`docker
volume ls` cross-referenced against what's actually supposed to be
persistent) that nothing currently unattached is data anyone needs, and
strongly prefer explicit `docker volume rm <name>` for anything you can
name and reason about individually over the blanket `--volumes` flag.

**Lesson:** Docker's "in use" for volume-pruning purposes means "a
container object currently references it," not "this data matters" —
those are not the same thing, and the gap between them is exactly the
brief window every normal container recreation passes through. Treat
`--volumes` as the single most dangerous flag in this entire lab, not
`-a`.
