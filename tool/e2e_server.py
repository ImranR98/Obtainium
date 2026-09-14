#!/usr/bin/env python3
"""Static file server for the e2e suites.

Serves `build/e2e_assets` like `python3 -m http.server`, but requests under
`/slow/` are delayed by `E2E_SLOW_DELAY` seconds (default 8) before streaming
the same file. This lets the install suites observe that installs start while
other apps are still downloading (#2611). The server is threaded so parallel
downloads overlap instead of queueing.
"""
import http.server
import os
import sys
import time
from functools import partial

SLOW_PREFIX = '/slow/'


class Handler(http.server.SimpleHTTPRequestHandler):
    slow_delay = 8.0

    def do_GET(self):
        if self.path.startswith(SLOW_PREFIX):
            time.sleep(self.slow_delay)
            self.path = '/' + self.path[len(SLOW_PREFIX):]
        super().do_GET()

    def log_message(self, *args):
        pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    directory = sys.argv[2] if len(sys.argv) > 2 else '.'
    Handler.slow_delay = float(os.environ.get('E2E_SLOW_DELAY', '8'))
    handler = partial(Handler, directory=directory)
    with http.server.ThreadingHTTPServer(('0.0.0.0', port), handler) as httpd:
        httpd.serve_forever()


if __name__ == '__main__':
    main()
