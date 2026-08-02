#!/bin/bash
# Runs once, automatically, via docker-entrypoint-initdb.d on first init of
# the primary's (empty) data directory. Creates the replication role and
# opens pg_hba.conf for replication connections from the standby.
#
# Note: pg_hba.conf's "all" database field does NOT match the special
# "replication" pseudo-database — that needs its own explicit line.
set -e

psql -v ON_ERROR_STOP=1 --username postgres <<-EOSQL
  CREATE ROLE repl WITH REPLICATION LOGIN PASSWORD 'replpass';
EOSQL

echo "host replication repl all md5" >> "$PGDATA/pg_hba.conf"
