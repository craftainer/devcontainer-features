"""A stand-in for the two Keycloak endpoints the rest wrapper calls.

POST /realms/master/protocol/openid-connect/token returns an access token
for the admin-cli password grant when the (URL-decoded) user name and
password match argv[2] and argv[3], and a JSON 401 otherwise. Every other
request needs that token as its bearer (401 otherwise) and gets:

- /status/404: 404 with a JSON body {"error": "not found"};
- /status/500: 500 with the plain-text body "Internal Server Error: boom";
- /text: 200 with the plain-text body "plain text reply";
- anything else: 200 with its method, path, content type and body as JSON
  ("raw_body" as received, "body" parsed as JSON or null).

Listens on 127.0.0.1 at a free port and writes the port to argv[1].
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs

TOKEN = "mock-token-123"
TOKEN_PATH = "/realms/master/protocol/openid-connect/token"


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, data, content_type):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _reply(self, status, payload):
        self._send(status, json.dumps(payload).encode(), "application/json")

    def _text(self, status, text):
        self._send(status, text.encode(), "text/plain")

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length).decode() if length else ""

    def _handle(self):
        body = self._body()
        if self.command == "POST" and self.path == TOKEN_PATH:
            form = {k: v[0] for k, v in parse_qs(body, keep_blank_values=True).items()}
            expected = {
                "grant_type": "password",
                "client_id": "admin-cli",
                "username": self.server.user,
                "password": self.server.password,
            }
            if form == expected:
                self._reply(200, {"access_token": TOKEN, "token_type": "Bearer"})
            else:
                self._reply(401, {"error": "invalid_grant"})
            return
        if self.headers.get("Authorization") != f"Bearer {TOKEN}":
            self._reply(401, {"error": "unauthorized"})
            return
        if self.path == "/status/404":
            self._reply(404, {"error": "not found"})
            return
        if self.path == "/status/500":
            self._text(500, "Internal Server Error: boom")
            return
        if self.path == "/text":
            self._text(200, "plain text reply")
            return
        try:
            parsed = json.loads(body) if body else None
        except ValueError:
            parsed = None
        self._reply(
            200,
            {
                "method": self.command,
                "path": self.path,
                "content_type": self.headers.get("Content-Type"),
                "raw_body": body,
                "body": parsed,
            },
        )

    do_GET = do_POST = do_PUT = do_DELETE = _handle

    def log_message(self, *args):
        pass


def main():
    port_file, user, password = sys.argv[1:4]
    server = HTTPServer(("127.0.0.1", 0), Handler)
    server.user = user
    server.password = password
    # Written whole, then renamed, so a reader never sees a partial port.
    with open(f"{port_file}.tmp", "w") as f:
        f.write(str(server.server_address[1]))
    os.replace(f"{port_file}.tmp", port_file)
    server.serve_forever()


if __name__ == "__main__":
    main()
