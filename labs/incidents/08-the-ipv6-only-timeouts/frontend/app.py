#!/usr/bin/env python3
"""
Frontend for Incident 08. /checkout does the most ordinary thing a
frontend can do: call a downstream service and relay its response.
Nothing wrong lives in this file - `requests` resolves `backend` via
plain getaddrinfo() and tries the results in order, exactly like any
default HTTP client. There's no Happy Eyeballs racing here on
purpose: this is what a large share of real HTTP client libraries
actually do.
"""
import time

from flask import Flask, jsonify
import requests

app = Flask(__name__)

BACKEND_URL = "http://backend:8080/checkout"
BACKEND_TIMEOUT = 5  # seconds


@app.route("/health")
def health():
    return jsonify(status="ok"), 200


@app.route("/checkout", methods=["POST"])
def checkout():
    start = time.monotonic()
    try:
        r = requests.post(BACKEND_URL, timeout=BACKEND_TIMEOUT)
        elapsed = time.monotonic() - start
        return jsonify(status="ok", backend=r.json(), elapsed_seconds=round(elapsed, 2)), 200
    except requests.exceptions.RequestException as e:
        elapsed = time.monotonic() - start
        return jsonify(status="error", error=str(e), elapsed_seconds=round(elapsed, 2)), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
