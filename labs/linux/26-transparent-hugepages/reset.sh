#!/usr/bin/env bash
# Lab 26 reset — restores THP to 'always' (the incident state) so you
# can retry, regardless of what the system's setting was before.
set -uo pipefail

THP_PATH="/sys/kernel/mm/transparent_hugepage/enabled"

echo "[reset] setting THP back to 'always' (the incident state)..."
echo always | sudo tee "$THP_PATH" >/dev/null
cat "$THP_PATH"

echo "[reset] done. Re-run setup.sh if you also need the compiled test programs rebuilt."
