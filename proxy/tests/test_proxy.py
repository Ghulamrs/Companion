#!/usr/bin/env python3
"""End-to-end checks for the Companion proxy. No API key, no tokens spent.

    python3 proxy/tests/test_proxy.py

Starts a stub upstream and a PHP server, then drives the proxy over real HTTP.
The point of interest is not that the happy path returns text — it is that the
text arrives *spread out over time*. A proxy that buffers passes every other
check here and still makes the app look frozen for a whole turn.
"""

import http.client
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).parent
SENTINEL_KEY = "sk-ant-SENTINEL-DO-NOT-LEAK"
TOKEN = "test-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

failures = []
skipped = []
checks = 0


def check(name, condition, detail=""):
    global checks
    checks += 1
    if condition:
        print(f"  ok    {name}")
    else:
        print(f"  FAIL  {name}" + (f"  [{detail}]" if detail else ""))
        failures.append(name)


def skip(name, why):
    skipped.append(name)
    print(f"  skip  {name}\n        {why}")


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), 0.25):
                return True
        except OSError:
            time.sleep(0.05)
    return False


def post(port, body, token=TOKEN, method="POST", raw=None):
    """One request, returning (status, headers, body-as-text)."""
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=30)
    payload = raw if raw is not None else json.dumps(body)
    headers = {"content-type": "application/json"}
    if token is not None:
        headers["authorization"] = f"Bearer {token}"
    conn.request(method, "/v1/messages", payload, headers)
    response = conn.getresponse()
    text = response.read().decode("utf-8", "replace")
    conn.close()
    # PHP does not promise a case for header names, and it varies by path here.
    headers = {k.lower(): v for k, v in response.getheaders()}
    return response.status, headers, text


def turn(text, model="claude-sonnet-5", max_tokens=1024):
    return {
        "model": model,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": text}],
    }


def php_config(api_base):
    """The config file the proxy reads, written as PHP rather than translated
    from JSON — a naive `:` swap mangles the `//` in a URL."""
    return f"""<?php
return [
    'api_key'        => '{SENTINEL_KEY}',
    'proxy_tokens'   => ['{TOKEN}'],
    'allowed_models' => ['claude-sonnet-5'],
    'max_tokens_cap' => 4096,
    'api_base'       => '{api_base}',
];
"""


def main():
    upstream_port = free_port()
    proxy_port = free_port()

    config = HERE / ".config.php"
    config.write_text(php_config(f"http://127.0.0.1:{upstream_port}"))

    upstream = subprocess.Popen(
        [sys.executable, str(HERE / "fake_upstream.py"), str(upstream_port)]
    )
    env = dict(os.environ, COMPANION_CONFIG=str(config))
    php = subprocess.Popen(
        ["php", "-S", f"127.0.0.1:{proxy_port}", "-t", str(HERE.parent / "public"),
         str(HERE / "router.php")],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )

    try:
        if not (wait_for(upstream_port) and wait_for(proxy_port)):
            print("servers did not come up")
            return 1

        print("\nrefusals")
        status, headers, text = post(proxy_port, turn("hello"), method="GET")
        check("GET is refused with 405", status == 405, status)
        check("405 names the allowed method", headers.get("allow") == "POST")

        status, _, text = post(proxy_port, turn("hello"), token=None)
        check("no credential is 401", status == 401, status)
        check(
            "401 uses the Messages error envelope",
            json.loads(text)["error"]["type"] == "authentication_error",
        )

        status, _, _ = post(proxy_port, turn("hello"), token="wrong-token")
        check("wrong token is 401", status == 401, status)

        status, _, text = post(proxy_port, None, raw="{not json")
        check("malformed JSON is 400", status == 400, status)

        status, _, text = post(proxy_port, turn("hi", model="claude-opus-5"))
        check("model outside the allowlist is 400", status == 400, status)
        check("the refusal names the model", "claude-opus-5" in text)

        status, _, text = post(proxy_port, turn("hi", max_tokens=99999))
        check("max_tokens above the cap is 400", status == 400, status)
        check("the refusal is not silent clamping", "4096" in text)

        status, _, _ = post(proxy_port, {"model": "claude-sonnet-5", "max_tokens": 10})
        check("missing messages is 400", status == 400, status)

        print("\nrelay")
        status, headers, text = post(proxy_port, turn("hello"))
        check("happy path is 200", status == 200, status)
        check(
            "content-type is passed through as SSE",
            headers.get("content-type", "").startswith("text/event-stream"),
            headers.get("content-type"),
        )
        deltas = [
            json.loads(line[6:])
            for line in text.splitlines()
            if line.startswith("data: ")
        ]
        rendered = "".join(
            d["delta"]["text"] for d in deltas if d.get("type") == "content_block_delta"
        )
        check("every delta arrives", rendered == "chunk0 chunk1 chunk2 chunk3 chunk4 ", rendered)

        sent = json.loads((HERE / ".received-headers.json").read_text())
        lower = {k.lower(): v for k, v in sent.items()}
        check("the key is attached upstream", lower.get("x-api-key") == SENTINEL_KEY)
        check("the API version is set by the proxy", lower.get("anthropic-version") == "2023-06-01")
        check("the caller's bearer token is not forwarded", "authorization" not in lower)

        status, _, text = post(proxy_port, turn("error"))
        check("an upstream failure keeps its status", status == 400, status)
        check(
            "an upstream failure keeps its envelope",
            json.loads(text)["error"]["message"] == "stub says no",
        )

        print("\nnothing is buffered")
        conn = http.client.HTTPConnection("127.0.0.1", proxy_port, timeout=30)
        conn.request(
            "POST", "/v1/messages", json.dumps(turn("hello")),
            {"content-type": "application/json", "authorization": f"Bearer {TOKEN}"},
        )
        started = time.time()
        response = conn.getresponse()
        arrivals = []
        while True:
            piece = response.read1(4096)
            if not piece:
                break
            arrivals.append(time.time() - started)
        conn.close()

        check("first bytes arrive early", arrivals and arrivals[0] < 0.4, f"{arrivals[:1]}")
        check(
            "delivery is spread over the stream, not dumped at the end",
            len(arrivals) >= 4 and (arrivals[-1] - arrivals[0]) > 0.4,
            f"{len(arrivals)} writes over {arrivals[-1] - arrivals[0]:.2f}s"
            if arrivals else "no writes",
        )

        print("\ncancellation")
        (HERE / ".upstream-aborted").unlink(missing_ok=True)
        conn = http.client.HTTPConnection("127.0.0.1", proxy_port, timeout=30)
        conn.request(
            "POST", "/v1/messages", json.dumps(turn("long")),
            {"content-type": "application/json", "authorization": f"Bearer {TOKEN}"},
        )
        response = conn.getresponse()
        response.read1(512)
        conn.close()  # the app's stop button, in effect

        deadline = time.time() + 8
        aborted = False
        while time.time() < deadline:
            if (HERE / ".upstream-aborted").exists():
                aborted = True
                break
            time.sleep(0.1)
        if aborted:
            check("hanging up tears down the upstream request", True)
        else:
            # PHP's built-in server does not implement this: connection_aborted()
            # stays 0 for the whole stream and the script is killed outright
            # instead (measured, not assumed). Under Apache with php-fpm the
            # flag does get set, which is what the proxy relies on -- proved
            # separately by abort_probe.php, deployed against the real path.
            skip(
                "hanging up tears down the upstream request",
                "not observable under php -S; verify with proxy/tests/abort_probe.php",
            )

        print("\na config that is not PHP leaks nothing")
        # The mistake this guards against is easy and quiet: writing the config
        # as KEY=value instead of PHP. require() then echoes the file, and the
        # caller reads the credentials off the response.
        bad = HERE / ".bad-config.php"
        bad.write_text("CLAUDE_PROXY_TOKEN=hunter2-should-never-be-served\n")
        bad_port = free_port()
        bad_php = subprocess.Popen(
            ["php", "-S", f"127.0.0.1:{bad_port}", "-t", str(HERE.parent / "public"),
             str(HERE / "router.php")],
            env=dict(os.environ, COMPANION_CONFIG=str(bad)),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        try:
            wait_for(bad_port)
            status, _, text = post(bad_port, turn("hello"))
            check("a non-PHP config is refused", status == 500, status)
            check("its contents are never served", "hunter2" not in text, text[:120])
        finally:
            bad_php.terminate()
            bad.unlink(missing_ok=True)

        print("\nthe key stays server-side")
        leaked = False
        for probe in (turn("hello"), turn("error"), turn("hi", model="claude-opus-5")):
            _, headers, text = post(proxy_port, probe)
            if SENTINEL_KEY in text or any(SENTINEL_KEY in v for v in headers.values()):
                leaked = True
        check("no response ever contains the key", not leaked)

        status, _, text = post(proxy_port, turn("hello"), token="wrong-token")
        check("a rejection does not echo the presented token", "wrong-token" not in text)

    finally:
        php.terminate()
        upstream.terminate()
        config.unlink(missing_ok=True)

    passed = checks - len(failures)
    tail = f", {len(skipped)} skipped" if skipped else ""
    print(f"\n{passed}/{checks} checks passed{tail}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
