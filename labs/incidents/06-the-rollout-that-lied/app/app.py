#!/usr/bin/env python3
"""
checkout-api for Incident 06.

Nothing about the code here is subtle - it's a deliberately ordinary
Flask service with two routes. The incident lives entirely in *how this
same code gets deployed* (see manifests/checkout-api-v2.yaml), not in
any bug in this file.

GET  /healthz   - liveness/readiness target. Deliberately shallow: it
                   only proves the process is up and listening. It does
                   NOT touch Postgres. That gap is the point of this lab.
POST /checkout   - the real, customer-facing request path. Opens a fresh
                   Postgres connection per request (no pool, kept simple
                   on purpose) and inserts an order row. This is the
                   request that actually needs working DB credentials.
"""
import os

from flask import Flask, jsonify, request
import psycopg2

app = Flask(__name__)

DB_HOST = os.environ.get("DB_HOST", "postgres")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_USER = os.environ.get("DB_USER", "checkout")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
DB_NAME = os.environ.get("DB_NAME", "checkoutdb")
APP_VERSION = os.environ.get("APP_VERSION", "v1")


@app.route("/healthz")
def healthz():
    # This is what the Deployment's readinessProbe and livenessProbe
    # both call. It answers "is the Python process up and serving HTTP,"
    # nothing more - no connection to Postgres is attempted here.
    return jsonify(status="ok", version=APP_VERSION), 200


@app.route("/checkout", methods=["POST"])
def checkout():
    body = request.get_json(silent=True) or {}
    item = body.get("item", "widget")

    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            dbname=DB_NAME,
            connect_timeout=3,
        )
        cur = conn.cursor()
        cur.execute("INSERT INTO orders (item) VALUES (%s) RETURNING id", (item,))
        order_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        return jsonify(error="checkout failed", detail=str(e)), 500

    return jsonify(status="ok", order_id=order_id, version=APP_VERSION), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
