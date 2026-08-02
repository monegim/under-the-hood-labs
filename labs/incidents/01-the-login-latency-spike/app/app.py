#!/usr/bin/env python3
"""
Login service for Incident 01.

Nothing about this file is the point of the lab - it's a deliberately
ordinary Flask app with a connection pool, same as you'd find in any
real service. The incident lives in the `worker` container (see
worker.py) and in MySQL's max_connections, not in this code.
"""
import os
import time

from flask import Flask, jsonify, request
import mysql.connector
from mysql.connector import pooling

app = Flask(__name__)

DB_HOST = os.environ.get("DB_HOST", "mysql")
DB_USER = os.environ.get("DB_USER", "appuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "apppass")
DB_NAME = os.environ.get("DB_NAME", "appdb")
POOL_SIZE = int(os.environ.get("DB_POOL_SIZE", "10"))

# A perfectly normal, perfectly reasonably-sized connection pool.
pool = pooling.MySQLConnectionPool(
    pool_name="login_pool",
    pool_size=POOL_SIZE,
    host=DB_HOST,
    user=DB_USER,
    password=DB_PASSWORD,
    database=DB_NAME,
    connection_timeout=3,
)

# How many times / how long the app is willing to retry getting a MySQL
# connection before giving up and returning an error to the client. This
# retry loop is what turns "MySQL refused a new connection" into elevated
# *latency* rather than an instant failure - which is exactly why this
# incident shows up as slow logins, not just failed logins.
MAX_RETRIES = 3
RETRY_DELAY_SECONDS = 0.4


def get_connection_with_retry():
    last_error = None
    for attempt in range(MAX_RETRIES):
        try:
            return pool.get_connection()
        except mysql.connector.Error as e:
            last_error = e
            if attempt < MAX_RETRIES - 1:
                time.sleep(RETRY_DELAY_SECONDS)
    raise last_error


@app.route("/health")
def health():
    return jsonify(status="ok"), 200


@app.route("/login", methods=["POST"])
def login():
    body = request.get_json(silent=True) or {}
    username = body.get("username", "")
    password = body.get("password", "")

    try:
        conn = get_connection_with_retry()
    except mysql.connector.Error as e:
        return jsonify(error="database unavailable", detail=str(e)), 503

    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT id FROM users WHERE username = %s AND password = %s",
            (username, password),
        )
        row = cur.fetchone()
        cur.close()
    finally:
        conn.close()  # returns the connection to the pool

    if row is None:
        return jsonify(error="invalid credentials"), 401
    return jsonify(status="ok", user_id=row[0]), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
