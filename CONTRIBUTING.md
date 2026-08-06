# Contributing

New labs are very welcome — see the root [README.md](README.md) for the
list of levels still short of their target count. Pick a topic that
isn't already covered (check the existing labs under `labs/<level>/`
first) and open a PR.

## What a lab must have

Every lab lives in its own directory (`labs/<level>/NN-topic-name/`,
numbered within its level, not globally) and ships all six of these:

- **`README.md`** — `# Lab N — Title`, `## Objective` (1-2 lines),
  `## Why this matters`, `## Prerequisites` (with a check-first command
  block), numbered `## Step N` sections that build the incident, then
  `## Challenges` with **exactly 2** "break it" scenarios — no answers,
  no hints beyond what's needed to reproduce the failure. End with:
  "See `solution.md` only after you've formed your own diagnosis."
  (Level 6 — Incidents — uses a different shape: see
  [`labs/incidents/README.md`](labs/incidents/README.md) for that
  format, since there's no guided build for those.)
- **`solution.md`** — a postmortem per challenge, not a command dump:
  `**Check:**` / `**Diagnosis:**` / `**Fix:**` / `**Lesson:**`.
- **`CONCEPTS.md`** — `## What's actually going on` (3-6 paragraphs on
  the real mechanism, plain English, no fluff), `## Where this shows up
  in the real world`, `## Go deeper` (3-6 resources — books, docs,
  YouTube). **Every resource must be real.** Don't cite a book, article,
  or video you haven't verified exists — a fabricated citation is worse
  than no citation.
- **`setup.sh`** — builds the broken "before" state. Should be
  idempotent where practical; if it isn't safe to rerun as-is, say so in
  a comment and make sure `reset.sh` handles the teardown first.
- **`check.sh`** — verifies the incident is *currently* resolved. Exit
  `0` only if genuinely healthy, non-zero otherwise, with clear
  `[PASS]`/`[FAIL]` output. Check the observable symptom, not one
  specific fix path — a learner might reach a working state a different
  way than the one in `solution.md`.
- **`reset.sh`** — restores the broken state so a learner can retry
  (typically: clean up any fix, then rebuild via `setup.sh`).

Look at an existing complete lab before writing a new one —
[`labs/linux/11-disk-full-writes-fail/`](labs/linux/11-disk-full-writes-fail)
is a good reference for a single-VM lab with `setup.sh`;
[`labs/networking/03-static-routing/`](labs/networking/03-static-routing)
for a containerlab-based one;
[`labs/mysql/01-replication-lag-io-contention/`](labs/mysql/01-replication-lag-io-contention)
for a docker-compose one.

## Before opening a PR

- `bash -n` every script you added (no syntax errors).
- `chmod +x` every `.sh` file — CI checks this and will fail the build
  if you forget.
- Make sure every internal markdown link (e.g. links between labs)
  actually resolves to a real file.
- Read `.github/workflows/lint.yml` if you want to run the same checks
  locally before pushing — it's a handful of file-syntax and
  file-presence checks (no live execution, since these labs need real
  block devices, cgroups, and sudo that CI runners don't provide).

## What CI does and doesn't check

CI verifies structure and syntax (every lab has the required files,
every script parses, every internal link resolves). It does **not**
actually run `setup.sh`/`check.sh` against a live environment — these
labs need loop devices, cgroup v2, containerlab, kind, or real sudo
access that a GitHub Actions runner doesn't give you. If you can, dry-run
your lab end-to-end on an actual Linux VM before submitting, and say so
in your PR description. If you can't, say that too — an honestly-flagged
"not yet live-tested" lab is fine; a silently untested one that turns out
to be broken isn't.

## Style

Plain English, terse, commands over prose. No filler, no "newspaper
language." Every "break it" challenge should be a realistic failure mode
people actually hit in production — not a contrived toy bug.
