#!/usr/bin/env python3
"""
orders-service for Incident 03.

Nothing wrong lives in this file. Every order request calls
auth-service's /validate before confirming the order - a completely
ordinary "check the session is still valid" call. When auth-service
can't be reached (see auth/app.py), this shows up here as a 500/timeout,
which is exactly why this service is the one that gets paged first even
though it isn't the one that's actually broken.
"""
import os

import requests
from flask import Flask, jsonify

app = Flask(__name__)

AUTH_URL = os.environ.get("AUTH_URL", "http://auth:8000")


@app.route("/health")
def health():
    return jsonify(status="ok"), 200


@app.route("/orders/<int:order_id>")
def get_order(order_id):
    try:
        r = requests.post(f"{AUTH_URL}/validate", timeout=2)
        r.raise_for_status()
    except requests.RequestException as e:
        return jsonify(error="auth service unavailable", detail=str(e)), 500

    return jsonify(order_id=order_id, status="confirmed"), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8001, threaded=True)
