#!/usr/bin/env python3
"""
auth-service for Incident 03.

/validate is called by orders-service on every request to check a
session token. It writes an audit-log entry for each validation - a
perfectly normal-sounding compliance requirement - but the file handle
is never closed (kept alive in _leaked_handles on purpose, standing in
for a real "someone forgot .close()" bug). Every real call from
orders-service, and every call setup.sh makes directly, leaks one more
file descriptor that's never given back.

The container's nofile ulimit is capped low (see docker-compose.yml) so
this leak exhausts the process's file descriptor budget quickly instead
of over weeks in production.
"""
import os
import time
import uuid

from flask import Flask, jsonify

app = Flask(__name__)

# Kept alive on purpose - this list is the "leak." A correct version of
# this handler would use `with open(...) as f:` and never keep a
# reference around after the request.
_leaked_handles = []


@app.route("/health")
def health():
    return jsonify(status="ok"), 200


@app.route("/validate", methods=["POST"])
def validate():
    try:
        path = f"/tmp/audit-{uuid.uuid4().hex}.log"
        f = open(path, "a")
        f.write(f"validated at {time.time()}\n")
        f.flush()
        _leaked_handles.append(f)  # BUG: never closed
    except OSError as e:
        return jsonify(valid=False, error=str(e)), 500
    return jsonify(valid=True), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, threaded=True)
