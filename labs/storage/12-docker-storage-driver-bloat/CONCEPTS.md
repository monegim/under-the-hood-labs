# Lab 12 — Concept: Why Docker Storage Only Ever Grows Until Something Prunes It

## What's actually going on

Docker's `overlay2` storage driver builds every image as a stack of
read-only layers, and every running or stopped container gets its own
thin writable layer on top of whatever image it was started from.
Layers are content-addressed and shared: if two images share a common
base, that base layer is stored once on disk and referenced by both,
which is why image builds are fast to push/pull incrementally — but it
also means "how big is this one image" and "how much disk does removing
this image actually free" are different questions, since some of an
image's layers might still be in use by other images or containers.
Critically, none of this is garbage-collected automatically. Building a
new version of an image doesn't delete the old version's layers;
stopping a container doesn't remove its writable layer or free the space
it used; and named volumes, being intentionally decoupled from any
single container's lifecycle (that's the entire point of a named
volume — surviving container recreation), are never touched by any
container-level cleanup at all. Everything simply accumulates in
`/var/lib/docker` until an operator or a scheduled job explicitly runs
some form of prune.

`docker system df` exists because `df -h` on the host filesystem can
only ever answer "how full is this filesystem," never "what inside
Docker's data is actually reclaimable." `system df`'s summary breaks
total usage down by images, containers, local volumes, and (on newer
versions) build cache, each with a **RECLAIMABLE** column showing how
much of that category's space could be freed right now — critically,
"reclaimable" here means "not currently referenced by anything," not
"safe to delete regardless of what it's for." `system df -v` lists every
individual object with its size and reference count, which is the level
of detail you actually want before deciding what to remove, rather than
acting on the aggregate number alone.

The prune commands (`container prune`, `image prune`, `volume prune`,
`network prune`, and `system prune` as a combined shortcut for the
first three-ish) each define "unused" narrowly and conservatively by
default, then widen that definition under specific flags — and the
widening is exactly where the real risk lives. Plain `image prune`
removes only **dangling** images: layers with no tag pointing at them at
all, the least ambiguous "nobody could reference this by name" case that
exists. Adding `-a` changes the definition entirely, to "any image not
currently backing a container" — which sweeps in tagged images kept
around on purpose for rollback or infrequent use. Volumes get an even
stronger default protection: `system prune`, even with `-a`, never
touches volumes at all unless `--volumes` is passed explicitly, and even
then only volumes with **zero** containers (running or stopped)
currently referencing them are eligible — which sounds safe until you
notice that "container removed and about to be recreated against the
same named volume" is a completely ordinary, brief state most
persistent-data volumes pass through during any routine deploy, not a
sign the data is disposable.

## Where this shows up in the real world

Any host that does builds or redeploys regularly — CI runners, build
servers, any long-lived Docker host that isn't purely ephemeral —
accumulates dangling images and stopped containers continuously, and
`/var/lib/docker` silently filling the root filesystem (sometimes taking
down the entire host, not just Docker, since it's frequently on the same
partition) is one of the most common "why is this box out of disk" pages
for teams running Docker outside of fully managed container platforms.
The corresponding, equally common failure mode in the other direction is
a well-intentioned cron job running `docker system prune -a -f
--volumes` on a schedule without anyone having read exactly what each
flag expands the blast radius to include — and losing a database's data
volume during what looked like routine maintenance is a real, recurring
incident pattern reported across enough teams that it's practically a
Docker rite of passage.

## Go deeper

- **Website/docs:** Docker's own documentation on pruning
  (`docker system prune`, `docker image prune`, `docker volume prune`
  reference pages) is the canonical, authoritative source for exactly
  what each flag includes and excludes — check the installed version's
  `docker <command> prune --help` output directly, since flag behavior
  has evolved across Docker releases.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/ — for
  background on `overlayfs(8)`, the kernel filesystem `overlay2` is built
  on, useful for understanding the layer-sharing model underneath image
  storage.
- **Book:** *Systems Performance* — Brendan Gregg — general storage and
  filesystem chapters are useful background for reasoning about
  layered/copy-on-write storage behavior generally.
- **YouTube:** Learn Linux TV — https://www.youtube.com/@LearnLinuxTV —
  has Docker and container storage administration content covering
  cleanup and storage driver basics.

**Confidence flag:** the exact set of object categories included in
`docker system df`'s summary output (images/containers/local
volumes/build cache) and its exact column names have evolved across
Docker Engine versions and have **not** been verified live against a
specific installed version in this lab — the underlying concepts
(reclaimable vs. total, per-category breakdown) are stable and
high-confidence, but exact column text may differ slightly from what's
shown here depending on the Docker version installed by `setup.sh`. The
prune command flag semantics (`-a` widening "unused" for images;
`--volumes` being required and separately gated from `-a` for volumes)
are stable, well-documented Docker CLI behavior and are high-confidence.
