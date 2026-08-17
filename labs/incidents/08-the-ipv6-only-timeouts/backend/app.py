#!/usr/bin/env python3
"""
Backend for Incident 08. Listens on "::" (both IPv6 and, since
IPV6_V6ONLY isn't set, IPv4 too) so it's reachable over either address
family - nothing wrong lives in this file. /checkout does the most
ordinary thing a downstream service can do: some trivial work, then a
response.
"""
from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/health")
def health():
    return jsonify(status="ok"), 200


@app.route("/checkout", methods=["POST"])
def checkout():
    total = sum(range(1000))  # stand-in for "do some real work"
    return jsonify(status="ok", total=total), 200


if __name__ == "__main__":
    app.run(host="::", port=8080)
