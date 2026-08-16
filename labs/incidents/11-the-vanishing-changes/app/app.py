#!/usr/bin/env python3
"""
Notes service for Incident 11.

Nothing here is buggy in the "wrote broken code" sense - POST /save writes
to the primary and commits, full stop. GET /note reads from whichever host
READS_FROM points at. If that's "replica" (the default, and the incident),
a GET immediately after a POST can race the replica's own apply thread and
see the old row, or no row at all - not because anything was deleted, but
because MySQL replication is asynchronous and nobody told this app that.
"""
import os

from flask import Flask, jsonify, request
import mysql.connector

app = Flask(__name__)

PRIMARY_HOST = os.environ.get("PRIMARY_HOST", "primary")
REPLICA_HOST = os.environ.get("REPLICA_HOST", "replica")
DB_USER = os.environ.get("DB_USER", "root")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "rootpass")
DB_NAME = os.environ.get("DB_NAME", "appdb")
READS_FROM = os.environ.get("READS_FROM", "replica")  # "replica" (the bug) or "primary" (the fix)


def connect(host):
    return mysql.connector.connect(
        host=host,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        connection_timeout=5,
    )


@app.route("/health")
def health():
    conn = connect(PRIMARY_HOST)
    cur = conn.cursor()
    cur.execute("SELECT 1")
    cur.fetchone()
    cur.close()
    conn.close()
    return jsonify(status="ok", reads_from=READS_FROM), 200


@app.route("/save", methods=["POST"])
def save():
    body = request.get_json(silent=True) or {}
    note_id = str(body.get("id", ""))
    text = body.get("text", "")
    if not note_id:
        return jsonify(status="error", error="id is required"), 400

    conn = connect(PRIMARY_HOST)
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO notes (id, text) VALUES (%s, %s)
        ON DUPLICATE KEY UPDATE text = VALUES(text)
        """,
        (note_id, text),
    )
    conn.commit()
    cur.close()
    conn.close()
    return jsonify(status="saved", id=note_id, text=text), 200


@app.route("/note/<note_id>")
def get_note(note_id):
    host = PRIMARY_HOST if READS_FROM == "primary" else REPLICA_HOST
    conn = connect(host)
    cur = conn.cursor()
    cur.execute("SELECT text FROM notes WHERE id = %s", (note_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    if row is None:
        return jsonify(status="not_found", id=note_id, read_from=host), 404
    return jsonify(status="ok", id=note_id, text=row[0], read_from=host), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
