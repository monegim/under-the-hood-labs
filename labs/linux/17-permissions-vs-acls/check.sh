#!/usr/bin/env bash
# Lab 17 check — is the ACL fix actually in place on /srv/shared (teamB
# granted write access), and can bob actually write there?
set -uo pipefail

PASS=0

if [ ! -d /srv/shared ]; then
    echo "[FAIL] /srv/shared does not exist."
    exit 1
fi

echo "[check] getfacl /srv/shared:"
getfacl -p /srv/shared 2>&1

ACL_ENTRY=$(getfacl -p /srv/shared 2>/dev/null | grep -E '^group:teamB:')
if [ -z "$ACL_ENTRY" ]; then
    echo "[FAIL] no ACL entry for group:teamB found on /srv/shared."
    PASS=1
else
    echo "[check] found ACL entry: $ACL_ENTRY"
    # Expect at least write (w) permission for teamB, per solution.md's fix
    # (setfacl -m g:teamB:rwx /srv/shared).
    PERMS=$(echo "$ACL_ENTRY" | cut -d: -f3)
    if [[ "$PERMS" != *w* ]]; then
        echo "[FAIL] group:teamB ACL entry does not grant write: $ACL_ENTRY"
        PASS=1
    fi
fi

echo "[check] functional test: can bob actually write into /srv/shared?"
TESTFILE="/srv/shared/.check_bob_write_$$"
if sudo -u bob touch "$TESTFILE" 2>/dev/null; then
    echo "[check] bob successfully created $TESTFILE"
    sudo rm -f "$TESTFILE"
else
    echo "[FAIL] bob could not write to /srv/shared."
    PASS=1
fi

if [ "$PASS" -eq 0 ]; then
    echo "[PASS] /srv/shared has a working teamB ACL entry and bob can write."
    exit 0
else
    echo "[FAIL] incident not resolved - see details above."
    exit 1
fi
