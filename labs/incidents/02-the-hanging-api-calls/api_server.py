#!/usr/bin/env python3
"""
Minimal "report API" for Incident 02. Copied into the `api` containerlab
node by setup.sh and run in the background.

GET /health              -> trivial SELECT 1 against the DB
GET /report?customer_id= -> pulls every order row for that customer

Nothing in this file is broken - it shells out to the real `mysql` CLI
and reports how long that took. The incident lives entirely in the
network path between this container and the DB (see setup.sh / r1).
"""
import http.server
import json
import subprocess
import time
import urllib.parse

DB_HOST = "10.2.2.10"
DB_NAME = "appdb"


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/health":
            self._run_query("SELECT 1", timeout=5)
        elif parsed.path == "/report":
            qs = urllib.parse.parse_qs(parsed.query)
            try:
                customer_id = int(qs.get("customer_id", ["1"])[0])
            except ValueError:
                customer_id = 1
            self._run_query(
                f"SELECT * FROM orders WHERE customer_id={customer_id}",
                timeout=12,
            )
        else:
            self.send_response(404)
            self.end_headers()

    def _run_query(self, sql, timeout):
        start = time.monotonic()
        try:
            result = subprocess.run(
                ["mysql", "-h", DB_HOST, "-uroot", DB_NAME, "-N", "-e", sql],
                capture_output=True,
                timeout=timeout,
                text=True,
            )
            elapsed = time.monotonic() - start
            ok = result.returncode == 0
            body = json.dumps({
                "ok": ok,
                "rows": len(result.stdout.splitlines()) if ok else 0,
                "bytes": len(result.stdout),
                "elapsed_seconds": round(elapsed, 2),
                "stderr": result.stderr.strip() if not ok else "",
            }).encode()
            self.send_response(200 if ok else 502)
        except subprocess.TimeoutExpired:
            elapsed = time.monotonic() - start
            body = json.dumps({
                "ok": False,
                "error": "query timed out",
                "elapsed_seconds": round(elapsed, 2),
            }).encode()
            self.send_response(504)

        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass  # keep stdout clean; use tcpdump/docker logs for investigation


if __name__ == "__main__":
    http.server.HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
