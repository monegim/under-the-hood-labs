#!/usr/bin/env python3
"""
"loyalty-points-reconciler" - a background job that runs alongside the
login service, reconciling loyalty-point balances against an events
table.

This is the actual incident. It connects to MySQL directly (no pool,
no connection reuse - a classic "someone wrote a quick batch script"
pattern) and holds each connection open for a long time per unit of
work (SELECT SLEEP(...) stands in for a genuinely slow, unindexed
reconciliation query scanning a large table). It opens NUM_WORKERS of
these concurrently, forever, reconnecting immediately if a connection
drops.

MySQL's max_connections is deliberately modest (see docker-compose.yml
/ mysql/my.cnf). NUM_WORKERS below is sized so this job alone eats most
of that budget, leaving only a sliver for the login service's pool.
"""
import os
import time

import mysql.connector

DB_HOST = os.environ.get("DB_HOST", "mysql")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "apppass")
DB_NAME = os.environ.get("DB_NAME", "appdb")

NUM_WORKERS = int(os.environ.get("RECONCILER_WORKERS", "26"))
HOLD_SECONDS = int(os.environ.get("RECONCILER_HOLD_SECONDS", "20"))

import threading


def reconcile_loop(worker_id):
    while True:
        try:
            conn = mysql.connector.connect(
                host=DB_HOST,
                user=DB_USER,
                password=DB_PASSWORD,
                database=DB_NAME,
                connection_timeout=5,
            )
            cur = conn.cursor()
            # Stand-in for a slow, unindexed reconciliation query. In a
            # real incident this is a genuinely slow query holding a
            # connection, not a literal SLEEP - the effect on the
            # connection budget is identical either way.
            cur.execute(f"SELECT SLEEP({HOLD_SECONDS})")
            cur.fetchall()
            cur.close()
            conn.close()
        except mysql.connector.Error:
            # MySQL is at max_connections and refused us - back off
            # briefly and just try again. This retry-forever loop is
            # exactly why the incident doesn't self-resolve: the worker
            # keeps re-claiming any connection slot the instant one
            # frees up.
            time.sleep(1)


if __name__ == "__main__":
    threads = []
    for i in range(NUM_WORKERS):
        t = threading.Thread(target=reconcile_loop, args=(i,), daemon=True)
        t.start()
        threads.append(t)
        time.sleep(0.05)  # stagger startup slightly

    print(f"[worker] started {NUM_WORKERS} reconciler workers, "
          f"each holding a connection ~{HOLD_SECONDS}s at a time", flush=True)

    while True:
        time.sleep(30)
