#!/usr/bin/env bash
# Lab 8 — Why Is the Server Slow — reset.sh
#
# setup.sh isn't safe to call twice back-to-back on its own: it always
# starts a brand new `nohup report-generator.sh &` without checking for an
# existing one, so re-running it without cleanup first would leave
# multiple hog processes stacked on top of each other. It's also silent
# about the Challenge A (bare `yes` x N) and Challenge B (Python memory
# hog) processes, which it never created and doesn't know about.
#
# So this reset:
#   1. kills any report-generator.sh, bare `yes`, or Python memory-hog
#      process left over from the main lab or either challenge
#   2. re-runs setup.sh to rebuild the main lab's "before" state fresh
#
# Safe to run even if nothing is running, and safe to run twice in a row.
#
# Usage: sudo bash reset.sh
set -uo pipefail

echo "[reset] Lab 8 — Why Is the Server Slow"

for pat_desc in "report-generator.sh:-f" "yes:-x" "hogs.append:-f"; do
    PAT="${pat_desc%:*}"
    FLAG="${pat_desc#*:}"
    PIDS=$(pgrep "$FLAG" "$PAT" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        echo "[reset] killing process(es) matching '$PAT': $PIDS"
        # shellcheck disable=SC2086
        sudo kill -9 $PIDS 2>/dev/null || true
    else
        echo "[reset] no process matching '$PAT', skipping"
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[reset] re-running setup.sh to rebuild the incident..."
sudo bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
