#!/usr/bin/env python3
"""A stand-in for api.anthropic.com.

The proxy's job is to relay bytes and hold a key. Neither needs a real account
to test, and testing against the real API would spend tokens to learn nothing
the stub cannot show. What the stub adds is the ability to assert on things the
live API cannot report back: which headers arrived, and whether the upstream
connection was actually torn down when the client walked away.

Behaviour is chosen by the text of the last user message:

    error   ->  400 with a Messages-API error envelope
    long    ->  20 deltas, 200 ms apart, for the cancellation test
    other   ->   5 deltas, 150 ms apart
"""

import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).parent
HEADERS_FILE = HERE / ".received-headers.json"
ABORTED_FILE = HERE / ".upstream-aborted"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):  # keep the test output readable
        pass

    def do_POST(self):
        if self.path != "/v1/messages":
            self.send_error(404)
            return

        length = int(self.headers.get("content-length", 0))
        raw = self.rfile.read(length)

        HEADERS_FILE.write_text(json.dumps(dict(self.headers), indent=2))

        try:
            body = json.loads(raw)
            last = body["messages"][-1]["content"]
        except Exception:
            last = ""

        if last == "error":
            self.respond_error()
        elif last == "long":
            self.stream(count=20, delay=0.2)
        else:
            self.stream(count=5, delay=0.15)

    def respond_error(self):
        payload = json.dumps(
            {"error": {"type": "invalid_request_error", "message": "stub says no"}}
        ).encode()
        self.send_response(400)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def stream(self, count, delay):
        # An SSE body has no length to declare, so the end of the stream *is*
        # the close. Without this the reader waits for a terminator that a
        # keep-alive connection never sends.
        self.close_connection = True
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.send_header("cache-control", "no-cache")
        self.send_header("connection", "close")
        self.end_headers()

        def emit(event, data):
            chunk = f"event: {event}\ndata: {json.dumps(data)}\n\n".encode()
            self.wfile.write(chunk)
            self.wfile.flush()

        try:
            emit("message_start", {"type": "message_start"})
            for i in range(count):
                time.sleep(delay)
                emit(
                    "content_block_delta",
                    {
                        "type": "content_block_delta",
                        "delta": {"type": "text_delta", "text": f"chunk{i} "},
                    },
                )
            emit("message_stop", {"type": "message_stop"})
        except Exception as failure:
            # The proxy dropped us, which is exactly what a cancelled turn
            # should cause. Leave proof for the test, naming what happened so a
            # surprising cause is not mistaken for the expected one.
            ABORTED_FILE.write_text(type(failure).__name__)


if __name__ == "__main__":
    port = int(sys.argv[1])
    for stale in (HEADERS_FILE, ABORTED_FILE):
        stale.unlink(missing_ok=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
