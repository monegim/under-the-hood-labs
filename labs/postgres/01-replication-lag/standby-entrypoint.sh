#!/bin/bash
# Custom entrypoint for the standby: if PGDATA is empty, take a base
# backup from the primary with `pg_basebackup -R` (which writes
# standby.signal + primary_conninfo for us — the standard PG12+ way to
# stand up a streaming replica), then hand off to the normal image
# entrypoint so it starts postgres like it would for any other data dir.
set -e

PGDATA_DIR=/var/lib/postgresql/data

mkdir -p "$PGDATA_DIR"
chown -R postgres:postgres "$PGDATA_DIR"

if [ -z "$(ls -A "$PGDATA_DIR" 2>/dev/null)" ]; then
  echo "[standby] PGDATA is empty, waiting for primary to accept connections..."
  until pg_isready -h primary -U postgres -q; do
    sleep 1
  done

  echo "[standby] taking base backup from primary (pg_basebackup -R)..."
  export PGPASSWORD=replpass
  gosu postgres pg_basebackup -h primary -U repl -D "$PGDATA_DIR" -Fp -Xs -P -R
  echo "[standby] base backup complete; standby.signal + primary_conninfo written."
fi

# Challenge B raises max_standby_streaming_delay well above the 30s
# default so a recovery conflict produces an observable, sustained lag
# instead of an near-instant query cancellation — see README Challenge B.
exec docker-entrypoint.sh postgres \
  -c hot_standby_feedback=off \
  -c max_standby_streaming_delay=300000
