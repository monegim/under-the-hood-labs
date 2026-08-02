#!/usr/bin/env bash
# Lab 17 reset — strip all ACL entries (including default/recursive ones
# from the challenges) back to plain owner/group/other bits, then re-run
# setup.sh to recreate the original scenario. setup.sh's chmod/chown alone
# would NOT undo existing ACL entries, so this must happen first.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d /srv/shared ]; then
    echo "[reset] stripping all ACL entries (recursive + default) from /srv/shared..."
    sudo setfacl -R -b -k /srv/shared 2>/dev/null || true
fi

echo "[reset] re-running setup.sh to recreate the permissions-vs-acls incident..."
bash "$SCRIPT_DIR/setup.sh"

echo "[reset] done."
