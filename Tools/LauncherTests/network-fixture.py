# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Emre Aribulan

"""Exercise native icon requests against a local fixture, without real accounts/sites."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import struct
import subprocess
import sys
import threading
import time
import zlib


def chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))


png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 2, 2, 8, 6, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress((b'\0' + b'\xff\x40\x20\xff' * 2) * 2)) + chunk(b'IEND', b'')
white = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 2, 2, 8, 6, 0, 0, 0))
white += chunk(b'IDAT', zlib.compress((b'\0' + b'\xff\xff\xff\xff' * 2) * 2)) + chunk(b'IEND', b'')
requests = []
leaked_cookies = []
icons_enabled = True


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        global icons_enabled
        requests.append(self.path)
        if self.headers.get('Cookie') or self.headers.get('Authorization'):
            leaked_cookies.append(self.path)
        if self.path == '/slow':
            time.sleep(3)
        if self.path == '/auth':
            self.send_response(401)
            self.send_header('WWW-Authenticate', 'Basic realm="fixture"')
            self.end_headers()
            return
        if self.path in ('/redirect.png', '/loop'):
            self.send_response(302)
            self.send_header('Location', '/icon.png' if self.path == '/redirect.png' else '/loop')
            self.end_headers()
            return
        if self.path in ('/disable-icons', '/enable-icons'):
            icons_enabled = self.path == '/enable-icons'
            self.send_response(200)
            self.end_headers()
            return
        body = {
            '/': b'<link rel="icon" href="/bad.png"><link rel="icon" href="/redirect.png">',
            '/bad.png': b'<html>not an image</html>',
            '/icon.png': png,
            '/white.png': white,
            '/large': b'x' * 4096,
            '/streamed': b'x' * 4096,
        }.get(self.path)
        if not icons_enabled:
            body = None
        self.send_response(200 if body is not None else 404)
        self.send_header('Set-Cookie', 'fixture=must-not-be-reused; Path=/')
        if body is not None and self.path != '/streamed':
            self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body or b'')
        except (BrokenPipeError, ConnectionResetError):
            pass


with ThreadingHTTPServer(('127.0.0.1', 0), Handler) as server:
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        subprocess.run([sys.argv[1], str(server.server_port)], check=True, timeout=45)
        assert not leaked_cookies, 'icon requests must not reuse cookies or credentials'
        assert not any('/private' in path or 'token=' in path for path in requests), 'saved page path/query leaked during discovery'
        assert '/redirect.png' in requests and '/icon.png' in requests
        print('PASS: fixture confirms direct fetching, redirects and no cookies/private page query')
    finally:
        server.shutdown()
