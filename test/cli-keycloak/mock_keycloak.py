"""A stand-in for the two Keycloak endpoints the rest wrapper calls.

POST /realms/master/protocol/openid-connect/token returns an access token
for the admin-cli password grant when the user name and password match
argv[2] and argv[3], and 401 otherwise. Any other request with that token
as its bearer gets back its method, path and JSON body as JSON; without it,
401. Listens on 127.0.0.1 at a free port and writes the port to argv[1].
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs

TOKEN = "mock-token-123"
TOKEN_PATH = "/realms/master/protocol/openid-connect/token"


class Handler(BaseHTTPRequestHandler):
    def _reply(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length).decode() if length else ""

    def _handle(self):
        body = self._body()
        if self.command == "POST" and self.path == TOKEN_PATH:
            form = {k: v[0] for k, v in parse_qs(body).items()}
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
        self._reply(
            200,
            {
                "method": self.command,
                "path": self.path,
                "content_type": self.headers.get("Content-Type"),
                "body": json.loads(body) if body else None,
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
