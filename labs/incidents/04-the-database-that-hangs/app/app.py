#!/usr/bin/env python3
"""
Save-service for Incident 04.

Nothing wrong lives in this file. /save does the most ordinary thing an
app can do: INSERT a row, COMMIT, tell the user it worked. There's no
connection pool to exhaust and no retry logic to hide anything - if
this hangs, it hangs because MySQL itself is taking a long time to
finish the COMMIT, full stop.
"""
import os
import time

from flask import Flask, jsonify, request
import mysql.connector

app = Flask(__name__)

DB_HOST = os.environ.get("DB_HOST", "mysql")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "apppass")
DB_NAME = os.environ.get("DB_NAME", "appdb")


def connect():
    return mysql.connector.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        connection_timeout=5,
    )


@app.route("/health")
def health():
    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT 1")
    cur.fetchone()
    cur.close()
    conn.close()
    return jsonify(status="ok"), 200


@app.route("/save", methods=["POST"])
def save():
    body = request.get_json(silent=True) or {}
    payload = body.get("payload", "checkout-event")

    start = time.monotonic()
    conn = connect()
    cur = conn.cursor()
    cur.execute("INSERT INTO events (payload) VALUES (%s)", (payload,))
    conn.commit()  # this is the fsync-on-commit that can stall
    event_id = cur.lastrowid
    cur.close()
    conn.close()
    elapsed = time.monotonic() - start

    return jsonify(status="ok", event_id=event_id, elapsed_seconds=round(elapsed, 3)), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
