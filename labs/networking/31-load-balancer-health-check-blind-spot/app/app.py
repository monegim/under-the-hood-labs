#!/usr/bin/env python3
"""
Backend for Lab 31. /healthz always answers - it only proves the
process is alive and accepting connections, nothing more. /api/data
does the actual work a real client cares about. On BACKEND_ID=3, that
real work is broken (a stand-in for a bad deploy, a missing config
value, a dependency that only backend 3 lost access to) - but nothing
about that failure touches /healthz at all.
"""
import os

from flask import Flask, jsonify

app = Flask(__name__)
BACKEND_ID = os.environ.get("BACKEND_ID", "1")
BROKEN = os.environ.get("BROKEN", "false").lower() == "true"


@app.route("/healthz")
def healthz():
    return jsonify(status="ok", backend=BACKEND_ID), 200


@app.route("/api/data")
def data():
    if BROKEN:
        return jsonify(status="error", backend=BACKEND_ID, error="dependency unavailable"), 500
    return jsonify(status="ok", backend=BACKEND_ID, data=[1, 2, 3]), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
