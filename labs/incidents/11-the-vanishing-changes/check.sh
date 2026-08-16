#!/usr/bin/env bash
# Incident 11 check - mirrors how this was paged: "I saved my changes and
# they disappeared." Writes a note, then IMMEDIATELY reads it back, N
# times in a row. Every read-after-write has to return exactly what was
# just written - no exceptions, no "usually."
set -uo pipefail

APP_URL="${APP_URL:-http://localhost:8080}"
N="${N:-20}"

if ! curl -s -o /dev/null -w '%{http_code}' "$APP_URL/health" 2>/dev/null | grep -q 200; then
    echo "[FAIL] app is not reachable at $APP_URL/health"
    exit 1
fi

FAILS=0
for i in $(seq 1 "$N"); do
    id="check-$$-$i"
    text="value-$i-$RANDOM"

    save_body=$(curl -s -X POST "$APP_URL/save" \
        -H "Content-Type: application/json" \
        -d "{\"id\":\"$id\",\"text\":\"$text\"}")

    read_body=$(curl -s "$APP_URL/note/$id")
    read_text=$(echo "$read_body" | grep -o '"text":"[^"]*"' | head -1)

    if echo "$read_text" | grep -q "\"text\":\"$text\""; then
        echo "[check] #$i: save ok, immediate read matched ($read_body)"
    else
        echo "[check] #$i: MISMATCH - saved '$text', read back '$read_body'"
        FAILS=$((FAILS+1))
    fi
done

if [ "$FAILS" -eq 0 ]; then
    echo "[PASS] all $N read-after-write checks matched - incident resolved."
    exit 0
else
    echo "[FAIL] $FAILS/$N read-after-write checks did not match - incident not resolved."
    exit 1
fi
