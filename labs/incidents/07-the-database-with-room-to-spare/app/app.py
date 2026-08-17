#!/usr/bin/env python3
"""
Signup-service for Incident 07.

Nothing wrong lives in this file. /signup does the most ordinary thing
an app can do: INSERT a row, COMMIT, tell the user it worked. There's
no connection pool to exhaust and no retry logic hiding anything - if
this fails, it fails because Postgres itself couldn't complete the
write, full stop.
"""
import os

from flask import Flask, jsonify, request
import psycopg2

app = Flask(__name__)

DB_HOST = os.environ.get("DB_HOST", "postgres")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "apppass")
DB_NAME = os.environ.get("DB_NAME", "appdb")


def connect():
    return psycopg2.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASSWORD,
        dbname=DB_NAME,
        connect_timeout=5,
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


@app.route("/signup", methods=["POST"])
def signup():
    body = request.get_json(silent=True) or {}
    email = body.get("email", "user@example.com")

    try:
        conn = connect()
        cur = conn.cursor()
        cur.execute("INSERT INTO users (email) VALUES (%s) RETURNING id", (email,))
        user_id = cur.fetchone()[0]
        conn.commit()  # this is the write that can fail
        cur.close()
        conn.close()
        return jsonify(status="ok", user_id=user_id), 200
    except Exception as e:
        return jsonify(status="error", error=str(e)), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
