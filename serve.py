"""Serve the web app for development, telling browsers never to cache it.

Python's built-in server sends no cache headers, so browsers (including Safari on the
phone) can keep running an old app.js against a new index.html after an update.

Usage: python3 serve.py [port]   (default 8000; reachable from other devices on the Wi-Fi)
"""

import functools
import http.server
import os
import sys


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    web_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web")
    handler = functools.partial(NoCacheHandler, directory=web_dir)
    http.server.ThreadingHTTPServer(("", port), handler).serve_forever()
